require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'digest/sha1'
require 'tempfile'
require 'fileutils'

require 'photohunt'
require 'errors'
require 'database'
require 'models'

module Photohunt
	module Web
		class CommonWeb < Sinatra::Base
			include Photohunt::Errors
			include Photohunt::GameID
			include Photohunt::Database

			helpers do
				def authenticate
					@token = Token[params[:token]]
					raise NotAuthorizedResponse.new(:token => params[:token]) if @token == nil
					@game = @token.game
				end

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
						when "image/jpeg"
							exposure = EXIFR::JPEG.new(StringIO.new(data)).date_time.to_s
						when "image/tiff"
							exposure = EXIFR::TIFF.new(StringIO.new(data)).date_time.to_s
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
			end

			configure do
				enable :logging
			end
		end

		class API < CommonWeb
			configure do
				disable :show_exceptions, :dump_errors
			end

			before do
				@game = Game[GAME_ID]
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
				halt ex.http_code, ex.to_json
			end

			get '/error' do
				raise RuntimeException, "LEMONADE"
			end

			before do
				pass unless request.accept? 'application/json'
			end

			before '/info' do
				authenticate
			end

			before '/photos/*' do
				authenticate
			end

			helpers do
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

			post '/photos/new', :provides => :json do
				content_type = request.env["CONTENT_TYPE"]
				if content_type == nil || MIME::Types[content_type] != MIME::Types["multipart/form-data"]
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
				begin
					get_exposure(
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
						:team => team
					)
					add_clue_completions photo, json
				end

				respond guid
			end

			put '/photos/edit', :provides => :json do
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

			get '/clues', :provides => :json do
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

			get '/info', :provides => :json do
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

		class Base < CommonWeb
			before do
				@game = Game[GAME_ID]
			end

			configure :production do
				error do
					ex = env['sinatra.error']
					ex = UnspecResponse.new unless Response === ex
					halt ex.http_code, ex.message
				end
			end

			before '/clues' do
				authenticate_clues
			end

			get '/clues', :provides => :text do
				pass unless request.accept? 'text/plain'
				out = StringIO.new
				out.printf("Clue sheet for Photo Hunt\n\n")
				out.printf("%-20s %s\n", "Start Time: ", @game.start)
				out.printf("%-20s %s\n", "End Time: ", @game.end)
				out.printf("\n")
				@game.clues_dataset.order(:id).eager(:tags, :bonuses => proc{ |ds| ds.order(:id) }).all do |clue|
					out.printf("%-4s\t%+5d\t%s %s\n", "#{clue.id}.", clue.points, clue.description, clue.tags.empty? ? "" : clue.tags.map{ |t| t.tag })
					clue.bonuses.each do |bonus|
						out.printf("\t%+5d\t\t%s\n", bonus.points, bonus.description)
					end
				end
				out.rewind
				return out.read
			end

			# The zipfile library seems to create temporary working files in /tmp and
			# doesn't delete them. I can't help this
			get '/export.zip', :provides => :zip do
				pass unless request.accept? 'application/zip'
				pass if JudgesToken[params[:token]] == nil
				tempfile = Tempfile.new("photohunt-export")
				path = tempfile.path
				# TODO: This isn't secure
				tempfile.unlink
				Zip::ZipFile.open(path, Zip::ZipFile::CREATE) do |zipfile|
					dirbase = "photohunt"
					zipfile.dir.mkdir(dirbase)

					DB.transaction do
						@game.teams_dataset.order(:name).eager(:photos => proc{ |ds|
								ds.order(:submission).eager(:clue_completions => proc{ |ds|
									ds.order(:clue_id).eager(:clue, :bonus_completions => proc{ |ds|
										ds.order(:bonus_id).eager(:bonus)
									})
								})
						}).all do |team|
							photoctr = 1
							judged_dir = "#{dirbase}/#{team.name}"
							unjudged_dir = "#{judged_dir}/unjudged"
							zipfile.dir.mkdir(judged_dir)
							zipfile.dir.mkdir(unjudged_dir)

							zipfile.file.open("#{unjudged_dir}/#{team.name}.txt", "w") do |unjudged_doc|
							zipfile.file.open("#{judged_dir}/#{team.name}.txt", "w") do |judged_doc|
								s = "Team \"#{team.name}\"\n"
								judged_doc.puts s
								unjudged_doc.puts s

								team.photos.each do |photo|
									if photo.judge
										doc = judged_doc
										dir = judged_dir
									else
										doc = unjudged_doc
										dir = unjudged_dir
									end
									exposure = nil
									filename = photoctr.to_s
									mime = MIME::Types[photo.mime].first
									begin
										exposure = get_exposure(
											:photo => photo,
											:mime => mime
										)
									rescue ExifError => e
										dump_errors!(e)
									end
									filename += ".#{mime.extensions.first}" if mime != nil && mime.extensions != nil
									zipfile.file.open("#{dir}/#{filename}", "w") do |file|
										file.write(photo.data)
									end

									doc.printf("\n%d.\n", photoctr)
									format_time = lambda { |time| time.strftime("%r %D") }
									doc.printf("\tExposure Time:   %s\n", format_time.call(exposure)) if exposure != nil
									doc.printf("\tSubmission Time: %s %s\n", format_time.call(photo.submission), photo.submission > @game.end ? "LATE" : "")
									if photo.clue_completions.length != 0
										points = 0
										clue_str = StringIO.new
										clue_str.printf("\tClues:\n")
										photo.clue_completions.each do |clue_completion|
											clue = clue_completion.clue
											clue_str.printf("\t\t%4s\t%+d\t%s\n", "#{clue.id}.", clue.points, clue.description)
											points += clue.points
											clue_completion.bonus_completions.each do |bonus_completion|
												bonus = bonus_completion.bonus
												clue_str.printf("\t\t\t%+d\t\t%s\n", bonus.points, bonus.description)
												points += bonus.points
											end
										end
										doc.printf("\tPoints: %d\n", points)
										clue_str.rewind
										doc.printf("%s", clue_str.read)
									end

									if photo.notes != nil && photo.notes != ""
										doc.printf("\tNotes:\n")
										# TODO: Pretty-print this.
										doc.printf("\t\t%s\n", photo.notes)
									end

									photoctr += 1
									# This is a hack so that the gc can collect the data. It modifies sequel internals.
									# The photo object is now broken.
									photo.values[:data] = nil
								end
								end
							end
						end
					end
				end
				return File.open(path) do |file|
					File.unlink(path)
					file.read
				end
			end
		end
	end
end
