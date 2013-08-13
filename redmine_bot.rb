#!/usr/bin/env ruby
# encoding: UTF-8

require 'rubygems'
require 'media_wiki'
require 'active_resource'
require 'erb'
require 'net/smtp'

if ARGV.length != 4
  puts "usage: redmine_bot <mode (renew|umlauf|unhold|inventarcheck|inventarmails)> <username> <password> <api_key>"
  exit(-1)
end

MODE     = ARGV[0]
USERNAME = ARGV[1]
PASSWORD = ARGV[2]
APIKEY   = ARGV[3]

require './models/user.rb'
require './models/issue.rb'

if MODE == "umlauf"
  mw = MediaWiki::Gateway.new('https://wiki.piratenfraktion-nrw.de/api.php')
  mw.login(USERNAME, PASSWORD, 'Piratenfraktion NRW')

  umlaufbeschluesse = Issue.find(:all, :params => { :tracker_id => 13 })
  umlaufbeschluesse.each do |u|
    result = ERB.new(File.read('./tpl/umlaufbeschluss.erb')).result(u.get_binding)
    page_name = ('Protokoll:Beschlüsse/' + u.start_date + '_' + u.subject).gsub(' ', '_')
    unless mw.get(page_name)
      Issue.put(u.id, :issue => { :notes => "Zusammenfassung im Wiki: https://wiki.piratenfraktion-nrw.de/wiki/#{page_name}"})
    end
    mw.edit(page_name, result, :summary => 'RedmineBot')
    if DateTime.now > u.end_datetime
      puts "closing #{u.id}"
      Issue.put(u.id, :issue => { :status_id => 9 })
    end
  end
elsif MODE == "renew"
  morgen_wieder = Issue.find(:all, :params => { :status_id => 13 })
  morgen_wieder.each do |m|
    puts "renewing #{m.id}"
    Issue.put(m.id, :issue => { :status_id => 1 })
  end
elsif MODE == 'unhold'
  hold = Issue.find(:all, :params => { :status_id => 14 })
  hold.each do |h|
    if h.get_field('Zurückstellen bis')
      dt = DateTime.parse("#{h.get_field('Zurückstellen bis')}")
      if DateTime.now >= dt
        puts "unholding #{h.id}"
        Issue.put(h.id, :issue => { :status_id => 2 })
      end
    end
  end
elsif MODE == "inventarcheck"
  inventar = Issue.find(:all, :params => { :status_id => 18  })
  smtp = Net::SMTP.new('mail.piratenfraktion-nrw.de', 587)
  smtp.enable_starttls
  smtp.start('piratenfraktion-nrw.de', USERNAME, PASSWORD, :login)
  inventar.each do |i|
    dt = DateTime.parse("#{i.due_date}")
    if DateTime.now >= dt
      #puts "Inventaritem in Ticket \##{i.id} ist heute fällig"
      Issue.put(i.id, :issue => { :status_id => 22 })
      msg = ERB.new(File.read('./tpl/inventar_faellig.erb')).result(i.get_binding)
      msg.force_encoding('ASCII-8BIT')
      smtp.send_message msg, 'it+redmine@piratenfraktion-nrw.de', User.find(i.assigned_to.id).mail
    end
  end
  smtp.finish
  inventar = Issue.find(:all, :params => { :status_id => 22 })
  inventar.each do |i|
    dt = DateTime.parse("#{i.due_date}")
    if DateTime.yesterday >= dt
      #puts "Inventaritem in Ticket \##{i.id} ist überfällig"
      Issue.put(i.id, :issue => { :status_id => 21 })
    end
  end
elsif MODE == "inventarmails"
  inventar = Issue.find(:all, :params => { :status_id => 21 })
  smtp = Net::SMTP.new('mail.piratenfraktion-nrw.de', 587)
  smtp.enable_starttls
  smtp.start('piratenfraktion-nrw.de', USERNAME, PASSWORD, :login)
  inventar.each do |i|
    msg = ERB.new(File.read('./tpl/inventar_ueberfaellig.erb')).result(i.get_binding)
    msg.force_encoding('ASCII-8BIT')
    smtp.send_message msg, 'it+redmine@piratenfraktion-nrw.de', User.find(i.assigned_to.id).mail
  end
  smtp.finish
else
  puts 'unknown command'
end
