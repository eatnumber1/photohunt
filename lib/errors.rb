module Photohunt
	module Errors
		class Response
			attr_accessor :data, :message, :code

			def initialize(opts = {})
				@data = opts[:data] if opts[:data] != nil
				@message = opts[:message] if opts[:message] != nil
				@code = opts[:code] if opts[:code] != nil
			end

			def to_json
				{
					:data => @data,
					:message => @message,
					:code => @code
				}.to_json
			end
		end

		class SuccessResponse < Response
			def initialize(opts = {})
				@message = "No error occurred"
				@code = 0
				super(opts)
			end
		end

		class UnspecResponse < Response
			def initialize(opts = {})
				@message = "Unspecified error"
				@code = 1
				super(opts)
			end
		end

		class NotAuthorizedResponse < Response
			def initialize(opts = {})
				@message = "Authorization token invalid"
				@code = 2
				super(opts)
			end
		end

		class GameOverResponse < Response
			def initialize(opts = {})
				@message = "Photohunt competition is over"
				@code = 3
				super(opts)
			end
		end

		class NotFoundResponse < Response
			def initialize(opts = {})
				@message = "Photo not found"
				@code = 4
				super(opts)
			end
		end

		class BadContentResponse < Response
			def initialize(opts = {})
				@message = "Unknown content-type"
				@code = 4
				super(opts)
			end
		end
	end
end
