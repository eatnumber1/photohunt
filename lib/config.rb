require 'yaml'
require 'logger'

require 'photohunt'
require 'database'

module Photohunt
  module Config

    db_conf = YAML.load_file("config/database.yml")[ENV["RACK_ENV"]].symbolize_keys!
    log_conf = YAML.load_file("config/logging.yml")[ENV["RACK_ENV"]].symbolize_keys!

    if log_conf.has_key? :logfile
      logfile = File.new(log_conf[:logfile], "a+")
      # Apparently we can't do line buffering in ruby.
      logfile.sync = true
      $stdout.reopen(logfile)
      $stderr.reopen(logfile)
    end
    logger = Logger.new($stdout)

    if db_conf.has_key?(:debug) && db_conf[:debug]
      include Photohunt::Database
      DB.logger = logger
    end
  end
end
