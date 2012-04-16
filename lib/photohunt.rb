class Hash
	def symbolize_keys
		dup.symbolize_keys!
	end

	def symbolize_keys!
		keys.each do |key|
			self[(key.to_sym rescue key) || key] = delete(key)
		end
		self
	end
end

class DateTime
	def pretty
		strftime("%r %D")
	end
end

module Photohunt
	module GameID
		GAME_ID = "3CF33F29-DE6C-4C9D-ACA7-71E37A2EDFBE"
	end
end
