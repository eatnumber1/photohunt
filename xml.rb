require 'sequel'
Sequel::Model.plugin :xml_serializer

$:.unshift File.expand_path("../lib", __FILE__)
require 'photohunt'
require 'schema'
require 'models'
require 'xmlsimple'

include Photohunt::GameID
include Photohunt::Database

puts Game.to_xml
puts Team.to_xml
puts Photo.to_xml
puts ClueCompletion.to_xml
puts BonusCompletion.to_xml
puts Token.to_xml
puts JudgesToken.to_xml
puts Tag.to_xml
puts Clue.to_xml
puts Bonus.to_xml
