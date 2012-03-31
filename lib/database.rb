require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'digest/sha1'
require 'logger'

require 'gameid'

module Photohunt
	module Database
		include Photohunt::GameID

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
				foreign_key :clue_id, :clues, :null => false, :on_delete => :cascade
				foreign_key :tag_id, :tags, :null => false, :on_delete => :cascade
			end

			DB.create_table! :bonus_completions do
				foreign_key :clue_completion_id, :clue_completions, :null => false, :on_delete => :cascade
				foreign_key :bonus_id, :bonuses, :null => false, :on_delete => :cascade
			end
			
			DB.create_table! :clue_completions do
				primary_key :id
				foreign_key :photo_id, :photos, :null => false, :type => String, :on_delete => :cascade
				foreign_key :clue_id, :clues, :null => false, :on_delete => :cascade
			end

			DB.create_table! :bonuses do
				primary_key :id
				foreign_key :clue_id, :clues, :null => false, :on_delete => :cascade
				String :description, :null => false
				Integer :points, :null => false
			end

			DB.create_table! :tags do
				primary_key :id
				String :tag, :unique => true, :null => false
			end

			DB.create_table! :clues do
				primary_key :id
				foreign_key :game_id, :games, :null => false, :type => String, :on_delete => :cascade
				String :description, :null => false
				Integer :points, :null => false
			end

			DB.create_table! :tokens do
				foreign_key :team_id, :teams, :null => false, :on_delete => :cascade
				foreign_key :game_id, :games, :null => false, :type => String, :on_delete => :cascade
				String :token, :null => false, :primary_key => true
			end

			DB.create_table! :photos do
				foreign_key :team_id, :teams, :null => false, :on_delete => :cascade
				String :guid, :null => false, :primary_key => true
				File :data, :null => false
				FalseClass :judge, :null => true
				String :notes, :text => true, :null => true
				String :mime, :null => false
				DateTime :submission, :default => "datetime('now','localtime')".lit
			end
			
			DB.create_table! :teams do
				primary_key :id
				foreign_key :game_id, :games, :null => false, :type => String, :on_delete => :cascade
				String :name, :null => false
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
			many_to_one :clue
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
			one_to_many :photos, :eager => :clue_completions
			one_to_many :tokens
			many_to_one :game
		end

		# The way this is built, nobody can ever have duplicate pictures.
		# Not sure anymore that this is a good thing.
		class Photo < Sequel::Model
			unrestrict_primary_key
			one_to_many :clue_completions, :order => :clue_id, :eager => :bonus_completions
			many_to_one :team
		end

		class ClueCompletion < Sequel::Model
			many_to_one :photo
			many_to_one :clue, :eager => :bonuses
			one_to_many :bonus_completions, :order => :bonus_id
		end

		class BonusCompletion < Sequel::Model
			set_primary_key [:clue_completion_id, :bonus_id]
			many_to_one :clue_completion
			many_to_one :bonus
		end

		class Token < Sequel::Model
			unrestrict_primary_key
			many_to_one :team
			many_to_one :game
		end

		class Game < Sequel::Model
			unrestrict_primary_key
			one_to_many :teams, :order => :name
			one_to_many :clues, :order => :id, :eager => :bonuses
			one_to_many :tokens
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
			clue = Clue.create(
				:description => "Your team on Marketplace Mall island.",
				:points => 100,
				:game => game
			)
			game.add_clue(
				:description => "Your team in a bank vault.",
				:points => 1000
			)
			clue3 = Clue.create(
				:description => "Your team on a boat.",
				:points => 5,
				:game => game
			)
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
			data = nil
			guid = File.open("./tmp/photo") do |f|
				data = f.read
				Digest::SHA1.hexdigest(data)
			end
			team = Team.create(
				:name => "faggot",
				:game => game
			)
			Token.create(
				:token => "foo",
				:game => game,
				:team => team
			)
			BonusCompletion.create(
				:bonus => Bonus.create(
					:description => "with a goose",
					:points => 50,
					:clue => clue
				),
				:clue_completion => ClueCompletion.create(
					:clue => clue,
					:photo => Photo.create(
						:guid => guid,
						:judge => true,
						:notes => "With a goose!",
						:data => data,
						:mime => "image/jpeg",
						:team => team
					)
				)
			)
		end
	end
end
