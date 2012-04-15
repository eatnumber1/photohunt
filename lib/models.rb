require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'digest/sha1'
require 'logger'

require 'photohunt'
require 'database'

module Photohunt
	module Database
		include Photohunt::GameID

		Sequel::Model.plugin :json_serializer

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
			plugin :lazy_attributes, :data
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

		class JudgesToken < Sequel::Model
			unrestrict_primary_key
		end
	end
end
