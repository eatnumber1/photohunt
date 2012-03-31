require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'digest/sha1'
require 'tempfile'
require 'fileutils'
require 'json'

require 'gameid'
require 'errors'
require 'database'

module Photohunt
	module Web
		class API < Sinatra::Base
			include Photohunt::Errors
			include Photohunt::GameID
			include Photohunt::Database

			# TODO: Finish teams
			configure do
				disable :show_exceptions
			end

			error do
				# TODO: Find out why I can't make every error have a http_code.
				err = env["sinatra.error"]
				if err.respond_to? :http_code
					halt err.http_code, err.to_hash.to_json 
				else
					halt 500, err.message
				end
			end

			before '/clues' do
				@game = Game[GAME_ID]
			end

			before '/info' do
				@token = Token[params[:token]]
				@game = @token.game
				raise NotAuthorized if @token == nil
			end

			before '/photos/*' do
				@token = Token[params[:token]]
				@game = @token.game
				raise NotAuthorized if @token == nil
			end

			helpers do
				def respond(data)
					NoneError.new(:data => data).to_json
				end

				def add_clue_completions(photo, data)
					clues = {}
					data["clues"].each do |clue|
						clues[clue["id"]] = clue["bonus_id"]
					end
					@game.clues_dataset.filter(:id => clues.keys).all do |clue|
						clue_completion = ClueCompletion.create(
							:clue => clue,
							:photo => photo
						)
						# TODO Eventually: The SQL generated could be optimized more
						unless clues[clue.id].empty?
							clue.bonuses_dataset.filter(:id => clues[clue.id]).all do |bonus|
								clue_completion.add_bonus_completion(:bonus => bonus)
							end
						end
					end
				end
			end

			#after do
			#	p "hello world!"
			#end

			get '/error', :provides => 'json' do
				raise NotFoundError
			#	respond_with do |f|
			#		f.json do
			#			raise NotFoundError, "Test this"
			#		end
			#	end
			end

			post '/photos/new', :provides => 'json' do
				pass unless request.accept? 'application/json'

				# TODO: Check for multipart form upload
				data = params[:photo][:tempfile].read
				mime = params[:photo][:type]
				# TODO: Don't raise a StandardError here.
				raise StandardError, "Unknown content-type #{params[:json][:type]} for json body" unless params[:json][:type] == "application/json"
				json = JSON.parse(params[:json][:tempfile].read)
				guid = Digest::SHA1.hexdigest(data)

				DB.transaction do
					team = @token.team
					photo = team.photos_dataset.for_update[:guid => guid]
					if( photo == nil )
						photo = Photo.create(
							:guid => guid,
							:data => data,
							:judge => json["judge"],
							:notes => json["notes"],
							:mime => mime,
							:team => team
						)
					else
						photo.clue_completions_dataset.delete
					end
					add_clue_completions photo, json
				end

				respond guid
			end

			# TODO: CRAWFORD, Don't use this anymore.
			put '/photos/new', :provides => 'json' do
				pass unless request.accept? 'application/json'

				data = request.body.read
				guid = Digest::SHA1.hexdigest(data)
				DB.transaction do
					team = @token.team
					photo = team.photos_dataset.for_update[:guid => guid]
					if( photo == nil )
						photo = Photo.new(
							:guid => guid,
							:data => data,
							:mime => "image/jpeg"
						)
						team.add_photo(photo)
					end
				end
				{
					:code => 0,
					:message => "Crawford is a faggot.",
					:data => photo.guid
				}.to_json
			end

			put '/photos/edit', :provides => 'json' do
				pass unless request.accept? 'application/json'

				data = JSON.parse(request.body.read)
				DB.transaction do
					photo = @token.team.photos_dataset.for_update[:guid => params[:id]]
					raise NotFoundError, "Photo #{params[:id]} not found" if photo == nil
					photo.update(:judge => data["judge"], :notes => data["notes"])
					photo.clue_completions_dataset.delete
					add_clue_completions photo, data
				end

				respond nil
			end

			get '/clues', :provides => 'json' do
				pass unless request.accept? 'application/json'
				# TODO: Doing JSON.parse right after Clue.to_json is really inefficient
				respond JSON.parse(@game.clues.to_json(
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

			get '/info', :provides => 'json' do
				pass unless request.accept? 'application/json'
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

			get '/error', :provides => 'json' do
				raise Sequel::Rollback, "Test this"
			#	respond_with do |f|
			#		f.json do
			#			raise NotFoundError, "Test this"
			#		end
			#	end
			end

			get '/clues', :provides => 'text' do
				out = StringIO.new
				game = Game[GAME_ID]
				out.printf("Clue sheet for Photo Hunt\n\n")
				out.printf("%-20s %s\n", "Start Time: ", game.start)
				out.printf("%-20s %s\n", "End Time: ", game.end)
				out.printf("%-20s %d\n", "Max Photos: ", game.max_photos)
				out.printf("%-20s %d\n", "Max Judged Photos: ", game.max_judged_photos)
				out.printf("\n")
				game.clues.each do |clue|
					out.printf("%-4s\t%+5d\t%s\n", "#{clue.id}.", clue.points, clue.description)
					clue.bonuses.each do |bonus|
						out.printf("\t%+5d\t\t%s\n", bonus.points, bonus.description)
					end
				end
				out.rewind
				return out.read
			end

			# The zipfile library seems to create temporary working files in /tmp and
			# doesn't delete them. I can't help this
			get '/export.zip', :provides => 'zip' do
				pass unless request.accept? 'application/zip'
				# TODO: Add judges-only auth.

				tempfile = Tempfile.new("photohunt-export")
				path = tempfile.path
				# TODO: This isn't secure
				tempfile.unlink
				Zip::ZipFile.open(path, Zip::ZipFile::CREATE) do |zipfile|
					dirbase = "photohunt"
					zipfile.dir.mkdir(dirbase)

					DB.transaction do
						game = Game[GAME_ID]
						game.teams.each do |team|
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
									doc.printf("\tSubmission Time: %s %s\n", photo.submission, photo.submission > game.end ? "LATE" : "")
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
