#!/usr/bin/env ruby
# encoding: UTF-8

require 'rubygems'
require 'media_wiki'
require 'active_resource'
require 'erb'
require 'net/smtp'
require 'net/imap'
require 'mail'
require 'rest_client'


if ARGV.length < 4
  puts "usage: redmine_bot <mode (renew|umlauf|unhold|inventarcheck|inventarmails)> <username> <password> <api_key> [<issue_id>]"
  exit(-1)
end

MODE     = ARGV[0]
USERNAME = ARGV[1]
PASSWORD = ARGV[2]
APIKEY   = ARGV[3]
DRUCKSACHEN_MAIL_USER = ARGV[4]
DRUCKSACHEN_MAIL_PASSWORD = ARGV[5]
ISSUE    = ARGV[6]

WIKI_URL = 'https://wiki.piratenfraktion-nrw.de'
REDMINE_URL = 'https://redmine.piratenfraktion-nrw.de'

require './drucksachen_extractor.rb'
require './models/user.rb'
require './models/issue.rb'

if MODE == "umlauf"
  mw = MediaWiki::Gateway.new("#{WIKI_URL}/w/api.php")
  mw.login(USERNAME, PASSWORD, 'Piratenfraktion NRW')

  umlaufbeschluesse = []
  umlaufbeschluesse << Issue.find(ISSUE) unless ISSUE.nil?
  umlaufbeschluesse = Issue.find(:all, :params => { :tracker_id => 13, :limit => 99999, :status_id => "8" }) if ISSUE.nil?

  umlaufbeschluesse.each do |u|
    u.attachments = Issue.get(u.id, :include => :attachments)['attachments']
    result = ERB.new(File.read('./tpl/umlaufbeschluss.erb')).result(u.get_binding)
    page_name = ('Protokoll:Beschlüsse/' + u.start_date + '_' + u.subject).gsub(' ', '_')
    unless mw.get(page_name)
      Issue.put(u.id, :issue => { :notes => "Zusammenfassung im Wiki: #{WIKI_URL}/wiki/#{MediaWiki::wiki_to_uri(page_name)}"})
      u.attachments.each do |a|
        mw.upload(nil, 'filename' => a['filename'], 'url' => a['content_url'])
      end
    end
    mw.edit(page_name, result, :summary => 'RedmineBot')
    if Time.now.utc > u.end_datetime.to_time.utc
      puts "closing \##{u.id}"
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
        puts "unholding \##{h.id}"
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
elsif MODE == "drucksachen_opal"
  imap = Net::IMAP.new("mail.piratenfraktion-nrw.de", 993, true)
  imap.login(DRUCKSACHEN_MAIL_USER, DRUCKSACHEN_MAIL_PASSWORD)
  imap.select('INBOX/drucksachen_opal')
  uids = []
  imap.search(['SUBJECT', 'Parlamentspapiere']).each do |uid|
    uids << uid
    body = imap.fetch(uid,'RFC822')[0].attr['RFC822']
    mail = Mail.read_from_string(body)
    mail.attachments.each do |a|
      drucksachen = parseDrucksachen(a.body.decoded)
      drucksachen.each do |ds|
        ds_dl = RestClient.get(ds[:link])
        response = RestClient.post("#{REDMINE_URL}/uploads.json?key=#{APIKEY}", ds_dl, {
          :multipart => true,
          :content_type => 'application/octet-stream'
        })
        token = JSON.parse(response)['upload']['token']
        issue = Issue.new(
          :subject => "#{ds[:number]}: #{ds[:title]}",
          :project_id => 'Dokumente',
          :description => ds[:link],
          :tracker_id => 11,
          :uploads => [
            {
              :token => token,
              :filename => ds[:link].split('/').last,
              :description => ds[:number],
              :content => 'application/pdf'
            }
          ]
        )
        if issue.save
          puts '#'+issue.id
        else
          puts issue.errors.full_messages
        end
      end
    end
    imap.copy(uid, 'Trash')
    imap.store(uid, "+FLAGS", [:Deleted])
  end
  imap.expunge
  imap.logout
  imap.disconnect
else
  puts 'unknown command'
end
