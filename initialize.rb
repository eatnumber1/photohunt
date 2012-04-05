$:.unshift File.expand_path("../lib", __FILE__)
require 'database'

include Photohunt::Database

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
	Team.create(
		:name => "1337",
		:game => game
	)
end
