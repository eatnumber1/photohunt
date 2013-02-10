require 'database'
require 'models'

module Photohunt
	module XML
		class XMLModel
			include Photohunt::Database

			def _xml_name_proc(name)
				name[/(?:.+(?:\/|__))?(.+)/, 1]
			end

			def _dump_xml
				options = {
					:name_proc => method(:_xml_name_proc).to_proc
				}
				builder = Nokogiri::XML::Builder.new do |xml|
					xml.photohunt do
						options[:builder] = xml
						DB.transaction do
							Game.to_xml(options.merge(
								:include => {
									:teams => options.merge(
										:include => {
											:tokens => options.merge(
												:except => [:team_id, :game_id]
											),
											:photos => options
										},
										:except => :game_id
									),
									:clues => options
								}
							))
							JudgesToken.to_xml(options)
						end
					end
				end
				builder.to_xml
			end

			@@dump = nil

			def self.invalidate
				@@dump = nil
			end

			def get_xml
				@@dump = Nokogiri::XML(_dump_xml) if @@dump == nil
				@@dump
			end

			def method_missing(m, *args, &block)
				# "a" Works around a bug in ruby
				a = args
				a = [] if args.length == 0
				Nokogiri::XSLT(File.read("xslt/#{self.class.name[/.+::(.+)XML$/,1]}/#{m}.xsl")).transform(get_xml, Nokogiri::XSLT.method(:quote_params).call(*a)).root.to_xml
			end
		end

		class GameXML < XMLModel
		end

		class ClueXML < XMLModel
		end

		class TeamXML < XMLModel
		end

		class PhotoXML < XMLModel
		end

		class TokenXML < XMLModel
		end
	end
end
