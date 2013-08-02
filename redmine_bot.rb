#!/usr/bin/env ruby
# encoding: UTF-8

require 'rubygems'
require 'media_wiki'
require 'active_resource'
require 'erb'

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
    inventar.each do |i|
      dt = DateTime.parse("#{i.get_field('Abgabedatum')}")
      if DateTime.now > dt
        puts "Inventaritem in Ticket \##{i.id} ist überfällig"
        Issue.put(i.id, :issue => { :status_id => 21 })
      elsif DateTime.now = dt
        puts "Inventaritem in Ticket \##{i.id} ist heute fällig"
        #TODO check if this really works, I'm just guessing here
        Issue.put(i.id, :issue => { :status_id => 22, :comment => "Das Fälligkeitsdatum für das ausgeliehene Objekt ist erreicht. Bitte gib es heute bei der IT ab." })
      end
    end
elsif MODE == "inventarmails"
    inventar_üerfällig = Issue.find(:all, :params => { :status_id => 21 })
    inventar_überfällig.each do |i|
      #TODO send some semi-angry mail
    end
else
    puts 'unknown command'
end

