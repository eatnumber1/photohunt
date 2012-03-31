$:.unshift File.expand_path("../lib", __FILE__)
require 'web'

map '/' do
	run Photohunt::Web::Base
end

map '/api' do
	run Photohunt::Web::API
end

# vim:ft=ruby
