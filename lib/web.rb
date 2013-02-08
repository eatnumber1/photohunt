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

				def authenticate_judge
					@token = JudgesToken[params[:token]]
					raise NotAuthorizedResponse.new(:token => params[:token]) if @token == nil
				end
			end

			configure do
				enable :logging
			end
		end

		class User < CommonWeb
			before do
				content_type :text
				pass unless request.accept? "text/plain"
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

			get '/clues' do
				pass unless request.accept? 'text/plain'
				out = StringIO.new
				out.printf("Clue sheet for Photo Hunt\n\n")
				out.printf("%-20s %s\n", "Start Time: ", @game.start.pretty)
				out.printf("%-20s %s\n", "End Time: ", @game.end.pretty)
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
			get '/export.zip' do
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
						@game.teams_dataset.eager_graph({
							:photos => {
								:clue_completions => [
									:clue,
									{
										:bonus_completions => :bonus
									}
								]
							}
						}).order(:exposure.asc, :submission.asc).all do |team|
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

								digit_count = team.photos.length.to_s.length
								team.photos.each do |photo|
									if photo.judge
										doc = judged_doc
										dir = judged_dir
									else
										doc = unjudged_doc
										dir = unjudged_dir
									end
									s = StringIO.new
									s.printf "%0#{digit_count}d", photoctr
									photoctr_s = s.string
									filename = photoctr_s
									mime = MIME::Types[photo.mime].first
									filename += ".#{mime.extensions.first}" if mime != nil && mime.extensions != nil
									zipfile.file.open("#{dir}/#{filename}", "w") do |file|
										file.write(photo.data)
									end

									doc.printf("\n%s.\n", photoctr_s)
									doc.printf("\tExposure Time:   %s\n", photo.exposure.pretty) if photo.exposure != nil
									doc.printf("\tSubmission Time: %s %s\n", photo.submission.pretty, photo.submission > @game.end ? "LATE" : "")
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
										doc.printf("%s", clue_str.string)
									end

									if photo.notes != nil && photo.notes != ""
										doc.printf("\tNotes:\n")
										# TODO: Pretty-print this.
										doc.printf("\t\t%s\n", photo.notes)
									end

									photoctr += 1
									# Now that we're done with this photo, throw out the data (we can get it again later
									# with photo.data) so the gc can collect it.
									photo.values.delete(:data)
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
