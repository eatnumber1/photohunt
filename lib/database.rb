require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'digest/sha1'

#require 'logger'

module Photohunt
	module Database
		Sequel.inflections do |inflect|
			inflect.irregular "bonus", "bonuses"
		end

		DB = Sequel.connect("sqlite://photohunt.sql")
		#DB = Sequel.sqlite
		#DB.logger = Logger.new($stdout)
		#DB.sql_log_level = :debug
	end
end
