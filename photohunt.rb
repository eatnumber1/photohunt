require 'sinatra'
require 'json'
require 'digest/sha1'
require 'tempfile'
require 'fileutils'
require 'filemagic'
require 'filemagic/ext'
require 'mime/types'
require 'sequel'
require 'zip/zipfilesystem'
require 'exifr'


require 'logger'

GAME_ID = "3CF33F29-DE6C-4C9D-ACA7-71E37A2EDFBE"

Sequel.inflections do |inflect|
	inflect.irregular "bonus", "bonuses"
end

#DB = Sequel.connect("sqlite://photohunt.sql")
DB = Sequel.sqlite
DB.logger = Logger.new($stdout)
DB.sql_log_level = :debug

Sequel::Model.plugin :json_serializer

DB.transaction do
	DB.create_table! :clues_tags do
		foreign_key :clue_id, :clues, :null => false
		foreign_key :tag_id, :tags, :null => false
	end

	DB.create_table! :bonus_completions do
		foreign_key :clue_completion_id, :clue_completions, :null => false
		foreign_key :bonus_id, :bonuses, :null => false
	end
	
	DB.create_table! :clue_completions do
		primary_key :id
		foreign_key :photo_id, :photos, :null => false, :type => String
		foreign_key :clue_id, :clues, :null => false
	end

	DB.create_table! :bonuses do
		primary_key :id
		foreign_key :clue_id, :clues, :null => false
		String :description, :null => false
		Integer :points, :null => false
	end

	DB.create_table! :tags do
		primary_key :id
		String :tag, :unique => true, :null => false
	end

	DB.create_table! :clues do
		primary_key :id
		foreign_key :game_id, :games, :null => false, :type => String
		String :description, :null => false
		Integer :points, :null => false
	end

	DB.create_table! :tokens do
		primary_key :id
		foreign_key :team_id, :teams, :null => false
		String :token, :null => false
	end

	DB.create_table! :photos do
		foreign_key :team_id, :teams, :null => false
		String :guid, :null => false, :primary_key => true
		File :data, :null => false
		FalseClass :judge, :null => true
		String :notes, :text => true, :null => true
		DateTime :submission, :default => "datetime('now','localtime')".lit
	end
	
	DB.create_table! :teams do
		primary_key :id
		foreign_key :game_id, :games, :null => false, :type => String
		String :name, :null => false
		FalseClass :finished, :null => false, :default => false
	end

	DB.create_table! :games do
		String :id, :primary_key => true
		DateTime :start, :null => false
		DateTime :end, :null => false
		Integer :max_photos, :null => false
		Integer :max_judged_photos, :null => false
	end
end

class Bonus < Sequel::Model
end

class Clue < Sequel::Model
	one_to_many :bonuses, :order => :id
	many_to_many :tags
	many_to_one :game
end

class Tag < Sequel::Model
	def to_json(*opts)
		self.tag.to_json(opts)
	end
end

class Team < Sequel::Model
	one_to_many :photos
	one_to_many :tokens
	many_to_one :game
end

class Photo < Sequel::Model
	unrestrict_primary_key
	one_to_many :clue_completions, :order => :clue_id
	many_to_one :team
end

class ClueCompletion < Sequel::Model
	many_to_one :photo
	many_to_one :clue
	one_to_many :bonus_completions, :order => :bonus_id
end

class BonusCompletion < Sequel::Model
	set_primary_key [:clue_completion_id, :bonus_id]
	many_to_one :clue_completion
	many_to_one :bonus
end

class Token < Sequel::Model
	many_to_one :team
end

class Game < Sequel::Model
	unrestrict_primary_key
	one_to_many :teams, :order => :name
	one_to_many :clues, :order => :id
end

DB.transaction do
	# There can only be ONE of these, or it messes up the clue ID numbering
	game = Game.create(
		:id => GAME_ID,
		:start => Time.at(0),
		:end => Time.at(946702800),
		:max_photos => 30,
		:max_judged_photos => 24
	)
	team = Team.new(
		:name => "faggot",
		:finished => false
	)
	game.add_team(team)
	clue = Clue.new(
		:description => "Your team on Marketplace Mall island.",
		:points => 100
	)
	game.add_clue(clue)
	game.add_clue(
		:description => "Your team in a bank vault.",
		:points => 1000
	)
	clue3 = Clue.new(
		:description => "Your team on a boat.",
		:points => 5
	)
	game.add_clue(clue3)
	clue3.add_bonus(
		:description => "if it is in water",
		:points => 10
	)
	clue3.add_bonus(
		:description => "if it is a real boat",
		:points => 10
	)
	clue.add_tag(:tag => "Location")
	clue.add_tag(:tag => "Goose")
	bonus = Bonus.new(
		:description => "with a goose",
		:points => 50
	)
	clue.add_bonus(bonus)
	data = nil
	guid = File.open("b") do |f|
		data = f.read
		Digest::SHA1.hexdigest(data)
	end
	photo = Photo.new(
		:guid => guid,
		:judge => true,
		:notes => "With a goose!",
		:data => data
	)
	team.add_photo(photo)
	team.add_token(:token => "foo")
	clue_completion = ClueCompletion.new(:clue => clue)
	photo.add_clue_completion(clue_completion)
	clue_completion.add_bonus_completion(:bonus => bonus)
end

module PhotohuntError
	ERR_SUCCESS = { :code => 0, :message => "No error occurred" }
	ERR_UNSPEC = { :code => 1, :message => "Unspecified error. Message contains additional information" }
	ERR_NOTAUTH = { :code => 2, :message => "Authorization token invalid" }
	ERR_GAMEOVER = { :code => 3, :message => "Photohunt competition is over. No judged submissions allowed" }
	ERR_NOTFOUND = { :code => 4, :message => "Photo not found" }
end

def authenticate
	token = Token.filter(:token => params[:token]).first
	if( token == nil )
		halt 401, PhotohuntError::ERR_NOTAUTH.merge({ :data => nil }).to_json
	else
		return token.team
	end
end

put '/api/photos/new', :provides => 'json' do
	pass unless request.accept? 'application/json'
	team = authenticate

	data = request.body.read
	guid = Digest::SHA1.hexdigest(data)
	photo = Photo[guid]
	if( photo == nil )
		photo = Photo.new(
			:guid => guid,
			:data => data
		)
		team.add_photo(photo)
	end
	p team
	return PhotohuntError::ERR_SUCCESS.merge({ :data => photo.guid }).to_json
end

# TODO: Validate that the bonuses passed for a particular clue are legal
# bonuses for that clue.
put '/api/photos/edit', :provides => 'json' do
	pass unless request.accept? 'application/json'
	team = authenticate

	data = JSON.parse(request.body.read)
	photo = Photo.find(:guid => params[:id], :team => team)
	halt 404, PhotohuntError::ERR_NOTFOUND.merge({ :data => nil }).to_json if photo == nil
	DB.transaction do
		photo.update(:judge => data["judge"], :notes => data["notes"])
		data["clues"].each do |clue|
			clue_completion = ClueCompletion.new(:clue => Clue[clue["id"]])
			photo.add_clue_completion(clue_completion)
			clue["bonus_id"].each do |bonus_id|
				clue_completion.add_bonus_completion(:bonus => Bonus[bonus_id])
			end
		end
	end

	return PhotohuntError::ERR_SUCCESS.merge({ :data => nil }).to_json
end

get '/api/clues', :provides => 'json' do
	pass unless request.accept? 'application/json'
	# TODO: Doing JSON.parse right after Clue.to_json is really inefficient
	return PhotohuntError::ERR_SUCCESS.merge({ :data => JSON.parse(Clue.filter(:game => Game[GAME_ID]).to_json(
		:naked => true,
		:except => :game_id,
		:include => {
			:bonuses => {
				:except => :clue_id,
				:naked => true
			},
			:tags => {}
		}
	))}).to_json
end

get '/api/info', :provides => 'json' do
	pass unless request.accept? 'application/json'
	team = authenticate
	return PhotohuntError::ERR_SUCCESS.merge({ :data => {
		:team => team.name,
		:startTime => team.game.start,
		:endTime => team.game.end,
		:max_photos => team.game.max_photos,
		:max_judged_photos => team.game.max_judged_photos
	}}).to_json
end

get '/clues', :provides => 'text' do
	out = StringIO.new
	out.printf("Clue sheet for Photo Hunt\n\n")
	out.printf("%-20s %s\n", "Start Time: ", Game[GAME_ID].start)
	out.printf("%-20s %s\n", "End Time: ", Game[GAME_ID].end)
	out.printf("%-20s %d\n", "Max Photos: ", Game[GAME_ID].max_photos)
	out.printf("%-20s %d\n", "Max Judged Photos: ", Game[GAME_ID].max_judged_photos)
	out.printf("\n")
	Game[GAME_ID].clues.each do |clue|
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

		Game[GAME_ID].teams.each do |team|
			photoctr = 1
			curdir = "#{dirbase}/#{team.name}"
			zipfile.dir.mkdir(curdir)

			zipfile.file.open("#{curdir}/#{team.name}.txt", "w") do |doc|
				doc.puts "Team \"#{team.name}\"\n"

				team.photos.each do |photo|
					exposure = "unavailable"
					filename = photoctr.to_s
					mime = MIME::Types[String.file_type(photo.data, :mime)].first
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
					doc.printf("\tSubmission Time: %s %s\n", photo.submission, photo.submission > Game[GAME_ID].end ? "LATE" : "")
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
	return File.open(path) do |file|
		File.unlink(path)
		file.read
	end
end
