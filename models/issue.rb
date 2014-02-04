# encoding: UTF-8
class Issue < ActiveResource::Base
  headers['X-Redmine-API-Key'] = APIKEY
  self.site = REDMINE_URL
  self.format = :xml
  attr_accessor :attachments

  def end_date
    get_field 'End Datum'
  end

  def end_time
    get_field 'End Uhrzeit'
  end

  def end_datetime
    dt = DateTime.parse("#{end_date}T#{end_time}:00+01:00")
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
