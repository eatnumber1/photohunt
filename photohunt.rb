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

#Sequel::Model.plugin :json_serializer

Sequel.inflections do |inflect|
	inflect.irregular "bonus", "bonuses"
end

#DB = Sequel.connect("sqlite://photohunt.sql")
DB = Sequel.sqlite
DB.logger = Logger.new($stdout)
DB.sql_log_level = :debug

DB.transaction do
	DB.create_table! :clues_tags do
		foreign_key :clue_id, :clues, :null => false
		foreign_key :tag_id, :tags, :null => false
	end

	DB.create_table! :bonus_completions do
		foreign_key :clue_completion_id, :clue_completions
		foreign_key :bonus_id, :bonuses, :null => false
	end
	
	DB.create_table! :clue_completions do
		primary_key :id
		foreign_key :photo_id, :photos, :null => false, :type => :varchar
		#foreign_key :photo_id, :photos, :null => false
		foreign_key :clue_id, :clues, :null => false
	end

	DB.create_table! :bonuses do
		primary_key :id
		foreign_key :clue_id, :clues
		String :description, :null => false
		Integer :points, :null => false
	end

	DB.create_table! :tags do
		primary_key :id
		String :tag, :unique => true, :null => false
	end

	DB.create_table! :clues do
		primary_key :id
		foreign_key :game_id, :games, :null => false
		String :description, :null => false
		Integer :points, :null => false
	end

	DB.create_table! :tokens do
		primary_key :id
		foreign_key :team_id, :teams
		String :token, :null => false
	end

	DB.create_table! :photos do
		#primary_key :id
		foreign_key :team_id, :teams
		#String :guid, :null => false
		String :guid, :null => false, :primary_key => true
		#primary_key :guid, :null => false, :auto_increment => false, :type => :varchar
		File :data, :null => false
		FalseClass :judge
		String :notes, :text => true
		DateTime :submission, :default => "datetime('now','localtime')".lit
	end
	
	DB.create_table! :teams do
		primary_key :id
		foreign_key :game_id, :games
		String :name, :null => false
		FalseClass :finished, :null => false, :default => false
	end

	DB.create_table! :games do
		primary_key :id
		DateTime :start
		DateTime :end
		Integer :maxPhotos
		Integer :maxJudgedPhotos
	end
end

class Bonus < Sequel::Model
	def to_json(*opts)
		{
			:description => self.description,
			:points => self.points
		}.to_json(*opts)
	end
end

class Clue < Sequel::Model
	one_to_many :bonuses
	many_to_many :tags

	def to_json(*opts)
		{
			:description => self.description,
			:points => self.points,
			:tags => self.tags,
			:bonuses => self.bonuses
		}.to_json(*opts)
	end
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
	one_to_many :clue_completions
end

class ClueCompletion < Sequel::Model
	many_to_one :photo
	many_to_one :clue
	one_to_many :bonus_completions
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
	one_to_many :teams
	one_to_many :clues
end

DB.transaction do
	game = Game.create(
		:start => Time.at(0),
		:end => Time.at(946702800),
		:maxPhotos => 30,
		:maxJudgedPhotos => 24
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
	clue.add_tag(:tag => "Location")
	clue.add_tag(:tag => "Goose")
	bonus = Bonus.new(
		:description => "with a goose",
		:points => 1000
	)
	clue.add_bonus(bonus)
	Bonus.new(
		:description => "with a goose",
		:points => 1000
	)
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
	clue_completion = ClueCompletion.new(:photo => photo, :clue => clue)
	photo.add_clue_completion(clue_completion)
	bonus_completion = BonusCompletion.new(:clue_completion => clue_completion, :bonus => bonus)
	clue_completion.add_bonus_completion(bonus_completion)
end

module PhotohuntError
	ERR_SUCCESS = { :code => 0, :message => "No error occurred" }
	ERR_UNSPEC = { :code => 1, :message => "Unspecified error. Message contains additional information" }
	ERR_NOTAUTH = { :code => 2, :message => "Authorization token invalid" }
	ERR_GAMEOVER = { :code => 3, :message => "Photohunt competition is over. No judged submissions allowed" }
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
	return PhotohuntError::ERR_SUCCESS.merge({ :data => photo.guid }).to_json
end

put '/api/photos/edit', :provides => 'json' do
	pass unless request.accept? 'application/json'
	authenticate

	data = JSON.parse(request.body.read)
	# TODO: Handle calling edit on a photo that doesn't exist
	# TODO: Add a find filter on the team_id
	photo = Photo.find(:guid => params[:id])
	photo.update(:judge => data["judge"], :notes => data["notes"])
	data["clues"].each do |clue|
		photo.add_clue_completion(:clue => Clue[clue["id"]], :bonus => nil)
		clue["bonus_id"].each do |bonus_id|
			photo.add_clue_completion(:clue => Clue[clue["id"]], :bonus => Bonus[bonus_id])
		end
	end

	return PhotohuntError::ERR_SUCCESS.merge({ :data => nil }).to_json
end

get '/api/clues', :provides => 'json' do
	pass unless request.accept? 'application/json'
	return PhotohuntError::ERR_SUCCESS.merge({ :data => Clue.all }).to_json
end

get '/api/info', :provides => 'json' do
	pass unless request.accept? 'application/json'
	team = authenticate
	return PhotohuntError::ERR_SUCCESS.merge({ :data => {
		:team => team.name,
		:startTime => team.game.start,
		:endTime => team.game.end,
		:maxPhotos => team.game.maxPhotos,
		:maxJudgedPhotos => team.game.maxJudgedPhotos
	}}).to_json
end

# The zipfile library seems to create temporary working files in /tmp and
# doesn't delete them. I can't help this
get '/api/export.zip', :provides => 'zip' do
	pass unless request.accept? 'application/zip'
	# TODO: Add judges-only auth.

	tempfile = Tempfile.new("photohunt-export")
	path = tempfile.path
	# This isn't secure
	tempfile.unlink
	Zip::ZipFile.open(path, Zip::ZipFile::CREATE) do |zipfile|
		dirbase = "photohunt"
		zipfile.dir.mkdir(dirbase)

		Team.each do |team|
			photoctr = 1
			curdir = "#{dirbase}/#{team.name}"
			zipfile.dir.mkdir(curdir)

			zipfile.file.open("#{curdir}/#{team.name}.txt", "w") do |doc|
				doc.puts "Team #{team.name}\n"

				# TODO: Add submission time to the export file.
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
					doc.printf("\tSubmission Time: %s\n", photo.submission)
					# TODO: Tell if it's late.
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
