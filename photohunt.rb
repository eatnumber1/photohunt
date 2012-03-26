require 'sinatra'
require 'json'
require 'digest/sha1'
require 'tempfile'
require 'fileutils'
require 'filemagic'
require 'mime/types'
require 'sequel'

require 'logger'

Sequel.inflections do |inflect|
	inflect.irregular "bonus", "bonuses"
end

#DB = Sequel.connect("sqlite://photohunt.sql")
DB = Sequel.sqlite
DB.logger = Logger.new($stdout)
DB.sql_log_level = :debug

DB.transaction do
	DB.create_table? :bonuses do
		primary_key :id
		foreign_key :clue_id, :clues
		String :description, :null => false
		Integer :points, :null => false
	end

	DB.create_table? :clues_tags do
		foreign_key :clue_id, :clues, :null => false
		foreign_key :tag_id, :tags, :null => false
	end
	
	DB.create_table? :clue_completions do
		foreign_key :photo_id, :photos, :null => false
		foreign_key :clue_id, :clues, :null => false
		foreign_key :bonus_id, :bonuses
	end

	DB.create_table? :tags do
		primary_key :id
		String :tag, :unique => true, :null => false
	end

	DB.create_table? :clues do
		primary_key :id
		String :description, :null => false
		Integer :points, :null => false
	end
	
	DB.create_table? :teams do
		primary_key :id
		foreign_key :game_id, :games
		String :name, :null => false
		FalseClass :finished, :null => false, :default => false
	end

	DB.create_table? :tokens do
		primary_key :id
		foreign_key :team_id, :teams
		String :token, :null => false
	end

	DB.create_table? :photos do
		primary_key :id
		foreign_key :team_id, :teams
		String :hash, :null => false
		File :data, :null => false
		FalseClass :judge, :null => false, :default => false
		String :notes, :text => true
	end

	DB.create_table? :games do
		primary_key :id
		Time :start
		Time :end
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
	one_to_many :clue_completions
	
#	one_to_many :clues, :dataset => proc {
#		PhotoClueBonus[photo_id].join(Clue, :id => ).join(Bonus, :bonus_id)
#	}
end

class ClueCompletion < Sequel::Model
	no_primary_key
	many_to_one :photo
	many_to_one :clue
	many_to_one :bonus
end

class Token < Sequel::Model
	many_to_one :team
end

class Game < Sequel::Model
	one_to_many :teams
end

DB.transaction do
	game = Game.create(
		:start => Time.at(0),
		:end => Time.at(946702800),
		:maxPhotos => 30,
		:maxJudgedPhotos => 24
	)
	team = Team.create(
		:name => "faggot",
		:finished => false
	)
	game.add_team(team)
	clue = Clue.create(
		:description => "Your team on Marketplace Mall island.",
		:points => 100
	)
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
	hash = File.open("b") do |f|
		data = f.read
		Digest::SHA1.hexdigest(data)
	end
	photo = Photo.create(
		:hash => hash,
		:judge => true,
		:notes => "With a goose!",
		:data => data
	)
	team.add_photo(photo)
	team.add_token(:token => "foo")
	photo.add_clue_completion(:clue => clue, :bonus => nil)
	photo.add_clue_completion(:clue => clue, :bonus => bonus)
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
	authenticate
	file = Tempfile.new('photohunt-api-imagedata')
	begin
		file.write(request.body.read)
		file.close
		hash = Digest::SHA1.hexdigest(request.body.read)
		filename = hash + "." + FileMagic.open(:mime) do |fm|
			MIME::Types[fm.file(file.path)].first.extensions.first
		end
		FileUtils.mv(file.path, filename)
		logger.info("New photo #{filename}")
		return PhotohuntError::ERR_SUCCESS.merge({ :data => hash }).to_json
	ensure
		file.close
		file.unlink
	end
end

put '/api/photos/edit', :provides => 'json' do
	pass unless request.accept? 'application/json'
	authenticate

	data = JSON.parse(request.body.read)
	# TODO: Handle calling edit on a photo that doesn't exist
	photo = Photo.find(:hash => params[:id])
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
