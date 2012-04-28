require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'digest/sha1'

module Photohunt
	module Database
		Sequel.inflections do |inflect|
			inflect.irregular "bonus", "bonuses"
		end

		Bundler.require(db_config[:adapter])
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
		DB = RetryingDatabaseWrapper.new(Sequel.connect(db_config))
		DB.convert_tinyint_to_bool = true if DB.adapter_scheme == :mysql2
	end
end
