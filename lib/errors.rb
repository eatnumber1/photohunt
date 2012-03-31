module Photohunt
	module Errors
		ERR_SUCCESS = { :code => 0, :message => "No error occurred. Data may provide additional information." }
		ERR_UNSPEC = { :code => 1, :message => "Unspecified error. Data contains additional information" }
		ERR_NOTAUTH = { :code => 2, :message => "Authorization token invalid" }
		ERR_GAMEOVER = { :code => 3, :message => "Photohunt competition is over. No judged submissions allowed" }
		ERR_NOTFOUND = { :code => 4, :message => "Element not found. Data contains additional information" }

		class StandardError < Exception
			attr_reader :json_code, :http_code

			attr_reader :data

			alias_method :standard_error_initialize, :initialize
			def initialize(options = {})
				options = { :message => options } unless options.respond_to? :assoc
				options[:data] ||= nil
				@json_code = 1
				@http_code = 500 # Internal server error
				@data = options[:data]
				standard_error_initialize(options[:message])
			end

			def to_hash
				{
					:code => json_code,
					:message => message,
					:data => data
				}
			end

			def to_json
				to_hash.to_json
			end
		end

		class NotFoundError < StandardError
			def initialize(options = {})
				options = { :message => options } unless options.respond_to? :assoc
				options[:message] ||= "Resource not found"
				ret = super(options)
				@json_code = 4
				@http_code = 404
				ret
			end
		end

		class NoneError < StandardError
			def initialize(options = {})
				options = { :message => options } unless options.respond_to? :assoc
				options[:message] ||= "No error"
				ret = super(options)
				@json_code = 0
				@http_code = 200
				ret
			end
		end

		class NotAuthorized < StandardError
			def initialize(options = {})
				options = { :message => options } unless options.respond_to? :assoc
				options[:message] ||= "Authorization token invalid"
				ret = super(options)
				@json_code = 2
				@http_code = 401
				ret
			end
		end
	end
end
