require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'digest/sha1'
require 'tempfile'
require 'fileutils'

require 'gameid'
require 'errors'
require 'database'
require 'models'

module Photohunt
	module Web
		class API < Sinatra::Base
			include Photohunt::Errors
			include Photohunt::GameID
			include Photohunt::Database

			configure do
				disable :show_exceptions
			end

			error do
				ex = env['sinatra.error']
				ex = UnspecResponse.new unless Response === ex
				halt ex.http_code, ex.to_json
			end

			before do
				pass unless request.accept? 'application/json'
			end

			before '/clues' do
				@game = Game[GAME_ID]
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

				def authenticate
					@token = Token[params[:token]]
					raise NotAuthorizedResponse.new if @token == nil
					@game = @token.game
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
								clue.bonuses.reject{ |b| b.id != clues[clue.id] }.each do |bonus|
									clue_completion.add_bonus_completion(:bonus => bonus)
								end
							end
						end
					end
				end
			end

			before '/photos/new' do
				content_type = request.env["CONTENT_TYPE"]
				if content_type == nil || MIME::Types[content_type] != MIME::Types["multipart/form-data"]
					raise MalformedResponse.new(:message => "Expecting Content-Type multipart/form-data")
				end

				raise MalformedResponse.new(
					:message => "Unknown content-type #{params[:json][:type]} for json body"
				) unless params[:json][:type] == "application/json"
			end

			post '/photos/new', :provides => :json do
				data = params[:photo][:tempfile].read
				mime = params[:photo][:type]
				json = JSON.parse(params[:json][:tempfile].read)
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
						:startTime => team.game.start,
						:endTime => team.game.end,
						:max_photos => team.game.max_photos,
						:max_judged_photos => team.game.max_judged_photos
					})
				end
			end
		end

		class Base < Sinatra::Base
			include Photohunt::Errors
			include Photohunt::GameID
			include Photohunt::Database

			before do
				@game = Game[GAME_ID]
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

					# TODO: Put unjudged photos in a different dir.
					DB.transaction do
						@game.teams_dataset.order(:name).eager(:photos => proc{ |ds|
								ds.order(:submission).eager(:clue_completions => proc{ |ds|
									ds.order(:clue_id).eager(:clue, :bonus_completions => proc{ |ds|
										ds.order(:bonus_id).eager(:bonus)
									})
								})
						}).all do |team|
							photoctr = 1
							curdir = "#{dirbase}/#{team.name}"
							zipfile.dir.mkdir(curdir)

							zipfile.file.open("#{curdir}/#{team.name}.txt", "w") do |doc|
								doc.puts "Team \"#{team.name}\"\n"

								team.photos.each do |photo|
									exposure = "unavailable"
									filename = photoctr.to_s
									mime = MIME::Types[photo.mime].first
									if mime != nil
										case mime.content_type
										when "image/jpeg"
											exposure = EXIFR::JPEG.new(StringIO.new(photo.data)).date_time.to_s
										when "image/tiff"
											exposure = EXIFR::TIFF.new(StringIO.new(photo.data)).date_time.to_s
										end
										filename += ".#{mime.extensions.first}" if mime.extensions != nil
									end
									zipfile.file.open("#{curdir}/#{filename}", "w") do |file|
										file.write(photo.data)
									end

									doc.printf("\n%d.\n", photoctr)
									doc.printf("\tJudged: %s\n", photo.judge) unless photo.judge == nil
									doc.printf("\tExposure Time: %s\n", exposure)
									# TODO: Make sure updates don't change submission time.
									doc.printf("\tSubmission Time: %s %s\n", photo.submission, photo.submission > @game.end ? "LATE" : "")
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
										doc.printf("\tPoints: %+d\n", points)
										clue_str.rewind
										doc.printf("%s", clue_str.read)
									end

									if photo.notes != nil
										doc.printf("\tNotes:\n")
										# TODO: Pretty-print this.
										doc.printf("\t\t%s\n", photo.notes)
									end

									photoctr += 1

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
