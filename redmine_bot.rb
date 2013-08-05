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

template = %q{{{Umlaufbeschluss
|Startdatum=<%= start_date %>
|Enddatum=<%= end_date %>
|Enduhrzeit=<%= end_time %>
|Dafür=<%= pro %>
|Anzahl Dafür=<%= count_pro %>
|Dagegen=<%= contra %>
|Anzahl Dagegen=<%= count_contra %>
|Enthaltung=<%= abstitution %>
|Anzahl Enthaltung=<%= count_abstitution %>
|Ohne Teilnahme=<%= not_participating %>
|Anzahl ohne Teilnahme=<%= count_not_participating %>
|Nicht abgestimmt=<%= not_voted %>
|Anzahl ohne Stimme=<%= count_not_voted %>
|Beschlussthema=<%= subject %>
|Beschlusstext=<%= description %>
}}}

class User < ActiveResource::Base

end

class Issue < ActiveResource::Base
  headers['X-Redmine-API-Key'] = APIKEY
  self.site = 'https://redmine.piratenfraktion-nrw.de/'
  self.format = :xml

  def end_date
    get_field 'End Datum'
  end

  def end_time
    get_field 'End Uhrzeit'
  end

  def end_datetime
    dt = DateTime.parse("#{end_date}T#{end_time}:00+02:00")
    dt
  end

  def get_field(name)
    custom_fields.select{ |f| f.name == name }.first.value rescue false
  end

  def pro; get_names("Dafür"); end
  def count_pro; get_count("Dafür"); end

  def contra; get_names("Dagegen"); end
  def count_contra; get_count("Dagegen"); end

  def abstitution; get_names("Enthaltung"); end
  def count_abstitution; get_count("Enthaltung"); end

  def not_voted; get_names("Noch nicht abgestimmt"); end
  def count_not_voted; get_count("Noch nicht abgestimmt"); end

  def not_participating; get_names("Nimmt nicht Teil"); end
  def count_not_participating; get_count("Nimmt nicht Teil"); end

  def get_names(field)
    custom_fields.select { |f| f.value == field }.map{|f| f.name }.join(',')
  end

  def get_count(field)
    custom_fields.select { |f| f.name if f.value == field }.length
  end

  def get_binding
    binding
  end
end

if MODE == "umlauf"
  mw = MediaWiki::Gateway.new('https://wiki.piratenfraktion-nrw.de/api.php')
  mw.login(USERNAME, PASSWORD, 'Piratenfraktion NRW')

  umlaufbeschluesse = Issue.find(:all, :params => { :tracker_id => 13 })
  umlaufbeschluesse.each do |u|
    result = ERB.new(template).result(u.get_binding)
    page_name = 'Protokoll:Beschlüsse/' + u.start_date + '_' + u.subject
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
  Net::SMTP.start('mail.piratenfraktion-nrw.de', 25, 'piratenfraktion-nrw.de', "#{USERNAME}", "#{PASSWORD}") do |smtp|
    inventar.each do |i|
      dt = DateTime.parse("#{i.due_date}")
      if DateTime.now >= dt
        #puts "Inventaritem in Ticket \##{i.id} ist heute fällig"
        Issue.put(i.id, :issue => { :status_id => 22 })
        msg = <<END_OF_MESSAGE
From: Fraktions-IT-Autoreminder <it+redmine@piratenfraktion-nrw.de>
To: #{i.assigned_to.name} <#{User.find(:first, :params => { :id => i.assigned_to.id }).mail }>
Subject: [Inventar - Inventar \##{i.id}] (Fällig) #{i.subject}
Date: #{DateTime.now}

Hallo,
bitte gib das von dir ausliehene Objekt "#{i.subject}" (#{i.get_field('Typ')} von #{i.get_field('Hersteller')}) heute bei der Fraktions-IT zurück. Du hast dieses am #{i.start_date} erhalten, dabei wurde der heutige Tag als Rückgabedatum festgelegt.

Falls du das Objekt heute nicht zurückgeben kannst oder länger behalten willst, wende dich bitte an die Fraktions-IT.

Nähere Informationen findest du hier:
> https://redmine.piratenfraktion-nrw.de/issues/#{i.id}

-- 
Diese Mail wurde automatisiiert vom Inventarbot der Fraktions-IT verschickt.
END_OF_MESSAGE
        smtp.send_message msg, 'it+redmine@piratenfraktion-nrw.de', User.find(:first, :params => { :id => i.assigned_to.id }).mail
      end
    end
  end
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
  Net::SMTP.start('mail.piratenfraktion-nrw.de', 25, 'piratenfraktion-nrw.de', "#{USERNAME}", "#{PASSWORD}") do |smtp|
    inventar.each do |i|
      msg = <<END_OF_MESSAGE
From: Fraktions-IT-Autoreminder <it+redmine@piratenfraktion-nrw.de>
To: #{i.assigned_to.name} <#{User.find(:first, :params => { :id => i.assigned_to.id }).mail}>
Subject: [Inventar - Inventar \##{i.id}] (Überfällig) #{i.subject}
Date: #{DateTime.now}

Hallo,
das von dir ausliehene Objekt "#{i.subject}" (#{i.get_field('Typ')} von #{i.get_field('Hersteller')}) hat den Ausleihezeitraum überschritten. Du hast dieses am #{i.start_date} erhalten, dabei wurde der #{i.due_date} als Rückgabedatum festgelegt.

Bitte gib das Objekt so schnell wie möglich zurück oder wende dich an die Fraktions-IT. Bis dahin werden regelmäßig weitere Erinnerungsmails an dich gesendet werden.

Nähere Informationen findest du hier:
> https://redmine.piratenfraktion-nrw.de/issues/#{i.id}

-- 
Diese Mail wurde automatisiiert vom Inventarbot der Fraktions-IT verschickt.
END_OF_MESSAGE
      smtp.send_message msg, 'it+redmine@piratenfraktion-nrw.de', User.find(:first, :params => { :id => i.assigned_to.id }).mail
    end
  end
else
  puts 'unknown command'
end
