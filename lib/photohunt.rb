require 'yaml'
require 'logger'

class Hash
	def symbolize_keys
		dup.symbolize_keys!
	end

	def symbolize_keys!
		keys.each do |key|
			self[(key.to_sym rescue key) || key] = delete(key)
		end
		self
	end
end

class DateTime
	def pretty
		strftime("%r %D")
	end
end

module Photohunt
	module Logging
		if ENV.has_key? "RACK_ENV"
			LOG_CONF = YAML.load_file("config/logging.yml")[ENV["RACK_ENV"]].symbolize_keys!

			if LOG_CONF.has_key? :logfile
				logfile = File.new(LOG_CONF[:logfile], "a+")
				# Apparently we can't do line buffering in ruby.
				logfile.sync = true
				$stdout.reopen(logfile)
				$stderr.reopen(logfile)
			end
		else
			LOG_CONF = {}
		end
		LOGGER = Logger.new($stdout)
	end

	module GameID
		GAME_ID = "3CF33F29-DE6C-4C9D-ACA7-71E37A2EDFBE"
	end
end

