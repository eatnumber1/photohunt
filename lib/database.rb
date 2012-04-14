require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'digest/sha1'

require 'yaml'

module Photohunt
	module Database
		Sequel.inflections do |inflect|
			inflect.irregular "bonus", "bonuses"
		end

		config = { "debug" => false }.merge(YAML.load_file("config.yml")).symbolize_keys!
		Bundler.require(config[:database].symbolize_keys![:adapter])
		class RetryingDatabaseWrapper
			def initialize(db)
				@db = db
			end

			def method_missing(m, *args, &block)
				@db.send(m, *args, &block)
			end

			def transaction(opts = {}, &block)
				begin
					@db.transaction(opts, &block)
				rescue Sequel::DatabaseError => e
					@db.transaction(opts, &block)
				end
			end
		end
		DB = RetryingDatabaseWrapper.new(Sequel.connect(config[:database]))

		if config[:debug]
			require 'logger'
			DB.logger = Logger.new($stdout)
		end
	end
end
