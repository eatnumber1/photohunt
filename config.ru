if ENV['RACK_ENV'] == "production"
	log = File.new("log/sinatra.log", "a+")
	# Apparently we can't do line buffering in ruby.
	log.sync = true
	$stdout.reopen(log)
	$stderr.reopen(log)
end

$:.unshift File.expand_path("../lib", __FILE__)
require 'web'

map '/' do
	run Photohunt::Web::Base
end

map '/api' do
	run Photohunt::Web::API
end

# vim:ft=ruby
