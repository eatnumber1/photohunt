$:.unshift File.expand_path("../lib", __FILE__)
require 'web'

#disable :run
#disable :show_exceptions
#disable :raise_errors
#disable :dump_errors

map '/' do
	run Photohunt::Web::Base
end

map '/api' do
	run Photohunt::Web::API
end

# vim:ft=ruby
