require 'rubygems'
require 'bundler/setup'
Bundler.require(:default, :development)
#Bundler.require(:default, :production)

require 'digest/sha1'

#require 'logger'

module Photohunt
	module Database
		Sequel.inflections do |inflect|
			inflect.irregular "bonus", "bonuses"
		end

		# SQLite suffers from a "database is locked" race condition.
		DB = Sequel.connect("sqlite://sql/photohunt.sql")
		#DB = Sequel.connect(:adapter => "mysql", :user => "photohunt", :host => "db.csh.rit.edu", :database => "photohunt", :password => "")
		#DB = Sequel.sqlite
		#DB.logger = Logger.new($stdout)
		#DB.sql_log_level = :debug
	end
end
