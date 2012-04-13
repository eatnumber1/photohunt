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

		$config = { :debug => false }.merge(YAML.load_file("config.yml"))
		Bundler.require($config["database"]["adapter"])
		DB = Sequel.connect($config["database"])
		module DBConn
			def reconnect
				connect($config["database"])
			end

			def ensure_connect
				begin
					test_connection
				rescue
					reconnect
				end
			end
		end
		DB.extend(DBConn)

		if $config["debug"]
			require 'logger'
			DB.logger = Logger.new($stdout)
			DB.sql_log_level = :debug
		end
	end
end
