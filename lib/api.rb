require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'digest/sha1'
require 'tempfile'
require 'fileutils'
require 'uuid'

require 'photohunt'
require 'errors'
require 'database'
require 'models'
require 'xml'

module Photohunt
	module Web
		module API
			class CommonAPI < CommonWeb
				configure do
					disable :show_exceptions, :dump_errors
				end

				error do
					ex = env['sinatra.error']
					_ex = ex
					dump = lambda do
						dump_errors!(_ex)
					end
					if Response === ex
						if NotAuthorizedResponse === ex
							dump = lambda{ logger.warn("Unauthorized login with token #{ex.token}") }
						else
							# Do nothing
						end
					else
						ex = UnspecResponse.new
					end
					dump.call
					json_proc = proc {
						halt ex.http_code, { "Content-Type" => "application/json" }, ex.to_json
					}
					request.accept.each do |type|
						case type
						when 'application/json'
							json_proc.call
						when 'application/xml', 'text/xml'
							halt ex.http_code, { "Content-Type" => "application/xml" }, ex.to_xml
						end
					end
					json_proc.call
				end

				get '/error' do
					raise RuntimeException, "LEMONADE"
				end
			end

			class Management < CommonAPI
				include Photohunt::XML

				helpers do
					def respond(options = {}, &block)
						SuccessResponse.new.to_xml(
							options.merge({
								:name_proc => method(:xml_name_proc).to_proc
							}),
							&block
						)
					end

					def xml_name_proc(name)
						name[/(?:.+(?:\/|__))?(.+)/, 1]
					end

					def prepare_game
						raise NotFoundResponse.new(:message => "No game selected") if params[:game] == nil
						@game = Game[params[:game]]
					end

					def update_from_params(obj, params, except = [])
						params.each do |k, v|
							obj[k] = v if not except.include? k.to_sym
						end
						XMLModel.invalidate
					end

					def respond_with_id(options = {})
						id = nil
						DB.transaction do
							id = yield
						end
						respond(options) do |builder, options|
							builder.id id
						end
					end
				end

				before do
					content_type :xml
					authenticate_judge
				end

				helpers do
					def create_game(params)
						game = nil
						DB.transaction do
							game = Game.create(
								:id => UUID.new.generate,
								:start => params[:start],
								:end => params[:end],
								:max_photos => params[:max_photos],
								:max_judged_photos => params[:max_judged_photos]
							)
						end
						XMLModel.invalidate
						game
					end
				end

				get '/games' do
					respond do |builder, options|
						DB.transaction do
							builder << GameXML.new.games
							#Game.to_xml options
						end
					end
				end

				post '/games' do
					respond_with_id do
						(create_game params)[:id]
					end
				end

				delete '/games' do
					DB.transaction do
						Game[params[:id]].destroy
					end
					respond
				end

				put '/games' do
					respond_with_id do
						game = nil
						if Game[params[:id]] == nil then
							game = create_game params
						else
							game = Game.dataset.for_update[:id => params[:id]]
							update_from_params game, params
							game.save
						end
						game[:id]
					end
				end

				helpers do
					def create_team(params)
						team = nil
						DB.transaction do
							team = Team.create(
								:game_id => @game[:id],
								:name => params[:name]
							)
						end
						XMLModel.invalidate
						team
					end
				end

				before '/teams' do
					prepare_game
				end

				get '/teams' do
					respond do |builder, options|
						DB.transaction do
							#@game.teams_dataset.to_xml(options.merge(
							#	:except => :game_id
							#))
							builder << TeamXML.new.teams("game" => @game[:id])
						end
					end
				end

				post '/teams' do
					respond_with_id do
						(create_team params)[:id]
					end
				end

				delete '/teams' do
					DB.transaction do
						Team[params[:id]].destroy
					end
					respond
				end

				put '/teams' do
					team = nil
					DB.transaction do
						if Team[params[:id]] == nil then
							team = create_team params
						else
							team = Team.dataset.for_update[:id => params[:id]]
							update_from_params team, params
							team.save
						end
					end
					respond do |builder, options|
						builder.id team[:id]
					end
				end

				helpers do
					def create_clue(params)
						clue = nil
						DB.transaction do
							clue = Clue.create(
								:game => @game,
								:description => params[:description],
								:points => params[:points]
							)
						end
						XMLModel.invalidate
						clue
					end
				end

				before '/clues' do
					prepare_game
				end

				get '/clues' do
					respond do |builder, options|
						DB.transaction do
							#@game.clues_dataset.to_xml(options.merge(
							#	:except => :game_id
							#))
							builder << ClueXML.new.clues(
								"game" => @game[:id]
							)
						end
					end
				end

				post '/clues' do
					respond_with_id do
						(create_clue params)[:id]
						XMLModel.invalidate
					end
				end

				delete '/clues' do
					DB.transaction do
						Clue[params[:id]].destroy
					end
					XMLModel.invalidate
					respond
				end

				put '/clues' do
					respond_with_id do
						clue = nil
						if Clue[params[:id]] == nil then
							clue = create_clue params
						else
							clue = Clue.dataset.for_update[:id => params[:id]]
							update_from_params clue, params, [:token, :game]
							XMLModel.invalidate
							clue.save
						end
						clue[:id]
					end
				end

				before '/photos' do
					prepare_game
				end

				get '/photos' do
					respond do |builder, options|
						DB.transaction do
							#Team[params[:team_id]].photos_dataset.to_xml(
							#	options.merge(:except => [:team_id, :data])
							#)
							builder << PhotoXML.new.photos(
								"game" => @game[:id],
								"team" => params[:team_id])
						end
					end
				end

				get '/photos/*' do
					prepare_game
					Photo[request.path_info.split("/")[-1]].data
				end

				get '/dump' do
					respond(:validate => false) do |builder, options|
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
			end

			class Uploader < CommonAPI
				helpers do
					def authenticate_clues
						begin
							# This is done so that clients which only retrieve the clue sheet once can
							# successfully retrieve it even if the game hasn't started yet.
							authenticate
						rescue NotAuthorizedResponse
							@game = Game[GAME_ID]
							raise GameNotStartedResponse if @game.start > DateTime.now
						end
					end

					def get_exposure(opts = {})
						mime = opts[:mime]
						mime = MIME::Types[opts[:type]].first if mime == nil
						data = opts[:data]
						data = opts[:photo].data if data == nil
						exposure = nil
						return nil if mime == nil
						begin
						case mime.content_type
							when "image/jpeg", "image/tiff"
								exposure = EXIFR::JPEG.new(StringIO.new(data)).date_time.to_s
							end
						rescue => e
							raise ExifError.new(
								:guid => opts[:photo] == nil ? nil : opts[:photo].guid,
								:wrapped_exception => e
							)
						end
						if exposure != nil
							if exposure.strip.empty?
								exposure = nil
							else
								exposure = DateTime.parse(exposure)
							end
						end
						return exposure
					end

					def respond(data)
						SuccessResponse.new(:data => data).to_json
					end

					def add_clue_completions(photo, data)
						clues = {}
						data["clues"].each do |clue|
							clues[clue["id"]] = clue["bonus_id"]
						end
						DB.transaction do
							# TODO: Do this in fewer lines of code by loading the cluedb into a hash.
							cluedb = @game.clues_dataset.filter(:id => clues.keys).eager(:bonuses).all
							# Validate the clue IDs
							raise MalformedResponse.new(:message => "Not all clue IDs specified were found") unless cluedb.length == clues.keys.length
							# Validate the bonus IDs
							cluedb.each do |clue|
								bonuses = clues[clue.id]
								unless bonuses == nil || bonuses.empty?
									bonusdb_ids = clue.bonuses.map{ |b| b.id }
									bonuses.each do |bonus_id|
										raise MalformedResponse.new(:message => "Bonus ID #{bonus_id} for clue ID #{clue.id} not found") unless bonusdb_ids.include? bonus_id
									end
								end
							end
							# Add the completions
							cluedb.each do |clue|
								clue_completion = ClueCompletion.create(
									:clue => clue,
									:photo => photo
								)
								bonuses = clues[clue.id]
								unless bonuses == nil || bonuses.empty?
									clue.bonuses.reject{ |b| ! clues[clue.id].include? b.id }.each do |bonus|
										clue_completion.add_bonus_completion(:bonus => bonus)
									end
								end
							end
						end
					end
				end

				before '/info' do
					authenticate
				end

				before '/photos/*' do
					authenticate
				end

				post '/photos/new' do
					ct = request.env["CONTENT_TYPE"]
					if ct == nil || MIME::Types[ct] != MIME::Types["multipart/form-data"]
						raise MalformedResponse.new(:message => "Expecting Content-Type multipart/form-data")
					end

					raise MalformedResponse.new("No JSON body provided") if params[:json] == nil
					unless String === params[:json]
						raise MalformedResponse.new(
							:message => "Unknown content-type #{params[:json][:type]} for json body"
						) unless params[:json][:type] == "application/json"
					end

					data = params[:photo][:tempfile].read
					mime = params[:photo][:type]
					exposure = nil
					begin
						exposure = get_exposure(
							:data => data,
							:type => mime
						)
					rescue ExifError => e
						raise MalformedResponse.new(
							:message => "Bad EXIF data",
							:wrapped_exception => e
						)
					end
					json = JSON.parse(String === params[:json] ? params[:json] : params[:json][:tempfile].read)
					guid = Digest::SHA1.hexdigest(data)

					DB.transaction do
						team = @token.team
						photo = team.photos_dataset.for_update[:guid => guid]
						photo.delete if photo != nil
						photo = Photo.create(
							:guid => guid,
							:data => data,
							:judge => json["judge"],
							:notes => json["notes"],
							:mime => mime,
							:team => team,
							:exposure => exposure
						)
						add_clue_completions photo, json
					end

					respond guid
				end

				put '/photos/edit' do
					data = JSON.parse(request.body.read)
					DB.transaction do
						photo = @token.team.photos_dataset.for_update[:guid => params[:id]]
						raise NotFoundResponse.new(:message => "Photo #{params[:id]} not found") if photo == nil
						photo.update(:judge => data["judge"], :notes => data["notes"])
						photo.clue_completions_dataset.delete
						add_clue_completions photo, data
					end

					respond nil
				end

				before '/clues' do
					authenticate_clues
				end

				get '/clues' do
					# TODO: Doing JSON.parse right after Clue.to_json is really inefficient
					respond JSON.parse(@game.clues_dataset.eager(:tags, :bonuses).to_json(
						:naked => true,
						:except => :game_id,
						:include => {
							:bonuses => {
								:except => :clue_id,
								:naked => true
							},
							:tags => {}
						}
					))
				end

				get '/info' do
					DB.transaction do
						team = @token.team
						respond({
							:team => team.name,
							:startTime => team.game.start.iso8601,
							:endTime => team.game.end.iso8601,
							:maxPhotos => team.game.max_photos,
							:maxJudgedPhotos => team.game.max_judged_photos
						})
					end
				end
			end
		end
	end
end
