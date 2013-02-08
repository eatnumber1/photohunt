$:.unshift File.expand_path("../lib", __FILE__)
require 'web'
require 'api'

map '/' do
	run Photohunt::Web::User
end

map '/api' do
	run Photohunt::Web::API::Uploader
end

map '/manage' do
  run Photohunt::Web::API::Management
end

map '/public' do
  run Rack::Directory.new("./public")
end

# vim:ft=ruby
