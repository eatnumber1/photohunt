require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'digest/sha1'

require 'photohunt'

module Photohunt
	module Database
		DB_CONF = YAML.load_file("config/database.yml")[ENV["RACK_ENV"]].symbolize_keys!

		Sequel.inflections do |inflect|
			inflect.irregular "bonus", "bonuses"
		end

		Bundler.require(DB_CONF[:adapter])
		class RetryingDatabaseWrapper
			def initialize(db)
				@db = db
			end

			def method_missing(m, *args, &block)
				@db.public_send(m, *args, &block)
			end

			def transaction(opts = {}, &block)
				begin
					@db.transaction(opts, &block)
				rescue Sequel::DatabaseError => e
					@db.transaction(opts, &block)
				end
			end
		end
		DB = RetryingDatabaseWrapper.new(Sequel.connect(DB_CONF))
		DB.convert_tinyint_to_bool = true if DB.adapter_scheme == :mysql2
		include Photohunt::Logging
		DB.logger = LOGGER if LOG_CONF.has_key?(:debug) && LOG_CONF[:debug]
	end
end
