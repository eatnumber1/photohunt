require 'yaml'

if ARGV.length < 1
	$stderr.puts "Usage: #{$0} yaml [yaml...]"
	exit false
end

$:.unshift File.expand_path("../lib", __FILE__)
require 'gameid'
require 'schema'
require 'models'

include Photohunt::GameID
include Photohunt::Database

data = {}
ARGV.each do |file|
	data = data.merge(YAML.load_file(file))
end

DB.transaction do
	if data["game"] != nil
		game_yml = data["game"]
		$game = Game.create(
			:id => GAME_ID,
			:start => game_yml["start"],
			:end => game_yml["end"],
			:max_photos => game_yml["max_photos"],
			:max_judged_photos => game_yml["max_judged_photos"]
		)
	else
		$game = Game[GAME_ID]
	end

	if data["clues"] != nil
		data["clues"].each do |clue|
			cluedb = Clue.create(
				:description => clue["description"],
				:points => clue["points"],
				:game => $game
			)
			if clue["bonuses"] != nil
				clue["bonuses"].each do |bonus|
					Bonus.create(
						:description => bonus["description"],
						:points => bonus["points"],
						:clue => cluedb
					)
				end
			end
			if clue["tags"] != nil
				clue["tags"].each do |tag|
					cluedb.add_tag(Tag.find_or_create(:tag => tag))
				end
			end
		end
	end

	if data["teams"] != nil
		data["teams"].each do |team|
			teamdb = Team.create(
				:name => team["name"],
				:game => $game
			)
			if team["tokens"] != nil
				team["tokens"].each do |token|
					Token.create(
						:token => token,
						:game => $game,
						:team => teamdb
					)
				end
			end
		end
	end

	if data["judge_tokens"] != nil
		data["judge_tokens"].each do |judge_token|
			JudgesToken.create(:token => judge_token)
		end
	end
end
