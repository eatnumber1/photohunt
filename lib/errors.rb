module Photohunt
	module Errors
		class Response < StandardError
			attr_accessor :data, :json_code, :http_code, :wrapped_exception

			def initialize(opts = {})
				@data = opts[:data] if opts[:data] != nil
				@json_code = opts[:json_code] if opts[:json_code] != nil
				@http_code = opts[:http_code] if opts[:http_code] != nil
				msg = opts[:message]
				wrapped_exception = opts[:wrapped_exception]
				if wrapped_exception != nil
					wrapped_exception_msg = "#{wrapped_exception.class} - #{wrapped_exception.message}"
					if msg == nil
						msg = wrapped_exception_msg
					else
						msg += " ( #{wrapped_exception_msg} )"
					end
				end
				super(msg)
				set_backtrace(wrapped_exception.backtrace) if wrapped_exception != nil
			end

			def to_json
				{
					:code => @json_code,
					:message => message,
					:data => @data
				}.to_json
			end

			def to_s
				return wrapped_exception != nil ? wrapped_exception.to_s : super.to_s
			end
		end

		class SuccessResponse < Response
			def initialize(opts = {})
				@json_code = 0
				@http_code = 200
				super({ :message => "No error occurred" }.merge(opts))
			end
		end

		class UnspecResponse < Response
			def initialize(opts = {})
				@json_code = 1
				@http_code = 500
				super(opts)
				super({ :message => "Unspecified error" }.merge(opts))
			end
		end

		class NotAuthorizedResponse < Response
			attr_reader :token

			def initialize(opts = {})
				@token = opts[:token] if opts[:token] != nil
				@json_code = 2
				@http_code = 401
				super(opts)
				super({ :message => "Authorization token invalid" }.merge(opts))
			end
		end

		class NotFoundResponse < Response
			def initialize(opts = {})
				@json_code = 3
				@http_code = 404
				super(opts)
				super({ :message => "Resource not found" }.merge(opts))
			end
		end

		class MalformedResponse < Response
			def initialize(opts = {})
				@json_code = 4
				@http_code = 415
				super({ :message => "Malformed message" }.merge(opts))
			end
		end

		class GameNotStartedResponse < Response
			def initialize(opts = {})
				@json_code = 5
				@http_code = 401
				super({ :message => "Game has not started" }.merge(opts))
			end
		end

		class ExifError < Response
			def initialize(opts = {})
				@json_code = 6
				if opts[:guid] != nil
					msg = "Bad exif metadata for photo #{opts[:guid]}"
					if opts[:message] != nil
						opts[:message] += ": #{msg}"
					else
						opts[:message] = msg
					end
				else
					{ :message => "Bad exif metadata" }.merge(opts)
				end
				super(opts)
			end
		end
	end
end
