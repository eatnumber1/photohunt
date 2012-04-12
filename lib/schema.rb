require 'rubygems'
require 'bundler/setup'
Bundler.require(:default)

require 'database'

include Photohunt::Database

module Photohunt
	module Database
		DB.transaction do
			DB.create_table? :games do
				String :id, :primary_key => true
				DateTime :start, :null => false
				DateTime :end, :null => false
				Integer :max_photos, :null => false
				Integer :max_judged_photos, :null => false
			end

			DB.create_table? :teams do
				primary_key :id
				foreign_key :game_id, :games, :null => false, :type => String, :on_delete => :cascade
				String :name, :null => false
			end

			DB.create_table? :judges_tokens do
				String :token, :null => false, :primary_key => true
			end

			DB.create_table? :tokens do
				foreign_key :team_id, :teams, :null => false, :on_delete => :cascade
				foreign_key :game_id, :games, :null => false, :type => String, :on_delete => :cascade
				# Tokens must be globally unique.
				String :token, :null => false, :primary_key => true
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

			DB.create_table? :bonuses do
				primary_key :id
				foreign_key :clue_id, :clues, :null => false, :on_delete => :cascade
				String :description, :null => false
				Integer :points, :null => false
			end

			DB.create_table? :photos do
				foreign_key :team_id, :teams, :null => false, :on_delete => :cascade
				String :guid, :null => false, :primary_key => true
				File :data, :null => false, :size => :long
				FalseClass :judge, :null => true
				String :notes, :text => true, :null => true
				String :mime, :null => false
				column :submission, "timestamp", :default => :now.sql_function
			end

			DB.create_table? :clues_tags do
				foreign_key :clue_id, :clues, :null => false, :on_delete => :cascade
				foreign_key :tag_id, :tags, :null => false, :on_delete => :cascade
			end

			DB.create_table? :clue_completions do
				primary_key :id
				foreign_key :photo_id, :photos, :null => false, :type => String, :on_delete => :cascade
				foreign_key :clue_id, :clues, :null => false, :on_delete => :cascade
			end

			DB.create_table? :bonus_completions do
				foreign_key :clue_completion_id, :clue_completions, :null => false, :on_delete => :cascade
				foreign_key :bonus_id, :bonuses, :null => false, :on_delete => :cascade
			end
		end
	end
end
