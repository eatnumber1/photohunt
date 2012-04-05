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

		DB = Sequel.connect("sqlite://photohunt.sql")
		#DB = Sequel.sqlite
		DB.logger = Logger.new($stdout)
		DB.sql_log_level = :debug

		Sequel::Model.plugin :json_serializer

		DB.transaction do
			DB.create_table? :clues_tags do
				foreign_key :clue_id, :clues, :null => false, :on_delete => :cascade
				foreign_key :tag_id, :tags, :null => false, :on_delete => :cascade
			end

			DB.create_table? :bonus_completions do
				foreign_key :clue_completion_id, :clue_completions, :null => false, :on_delete => :cascade
				foreign_key :bonus_id, :bonuses, :null => false, :on_delete => :cascade
			end
			
			DB.create_table? :clue_completions do
				primary_key :id
				foreign_key :photo_id, :photos, :null => false, :type => String, :on_delete => :cascade
				foreign_key :clue_id, :clues, :null => false, :on_delete => :cascade
			end

			DB.create_table? :bonuses do
				primary_key :id
				foreign_key :clue_id, :clues, :null => false, :on_delete => :cascade
				String :description, :null => false
				Integer :points, :null => false
			end

			DB.create_table? :tags do
				primary_key :id
				String :tag, :unique => true, :null => false
			end

			DB.create_table? :clues do
				primary_key :id
				foreign_key :game_id, :games, :null => false, :type => String, :on_delete => :cascade
				String :description, :null => false
				Integer :points, :null => false
			end

			DB.create_table? :tokens do
				foreign_key :team_id, :teams, :null => false, :on_delete => :cascade
				foreign_key :game_id, :games, :null => false, :type => String, :on_delete => :cascade
				String :token, :null => false, :primary_key => true
			end

			DB.create_table? :photos do
				foreign_key :team_id, :teams, :null => false, :on_delete => :cascade
				String :guid, :null => false, :primary_key => true
				File :data, :null => false
				FalseClass :judge, :null => true
				String :notes, :text => true, :null => true
				String :mime, :null => false
				DateTime :submission, :default => "datetime('now','localtime')".lit
			end

			DB.create_table? :teams do
				primary_key :id
				foreign_key :game_id, :games, :null => false, :type => String, :on_delete => :cascade
				String :name, :null => false
			end

			DB.create_table? :games do
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
			one_to_many :bonuses
			many_to_many :tags, :order => :tag
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

		# The way this is built, nobody can ever have duplicate pictures.
		# Not sure anymore that this is a good thing.
		class Photo < Sequel::Model
			unrestrict_primary_key
			one_to_many :clue_completions, :eager => :bonus_completions
			many_to_one :team
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
			unrestrict_primary_key
			many_to_one :team
			many_to_one :game
		end

		class Game < Sequel::Model
			unrestrict_primary_key
			one_to_many :teams
			one_to_many :clues
			one_to_many :tokens
		end
	end
end
