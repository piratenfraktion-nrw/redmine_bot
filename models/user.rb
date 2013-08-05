# encoding: UTF-8
class User < ActiveResource::Base
  headers['X-Redmine-API-Key'] = APIKEY
  self.site = 'https://redmine.piratenfraktion-nrw.de/'
  self.format = :xml
end
