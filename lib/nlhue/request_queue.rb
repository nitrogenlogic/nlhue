# A class for managing HTTP requests to a host.  Only allows one outstanding
# request to a given category, while allowing requests to unrelated categories.
# Categories default to path names.
# (C)2013 Mike Bourgeous

require 'eventmachine'
require 'em/protocols/httpclient'

module NLHue
	class RequestQueue
		attr_reader :host

		# Initializes a request queue with the given host, default
		# request timeout, and default POST/PUT content type.
		def initialize host, timeout=5, content_type='application/json;charset=utf-8'
			@host = host
			@default_type = content_type
			@default_timeout = timeout
			@request_queue = {}
		end

		# Changes the host name used by requests.
		def host= host
			@host = host
		end

		# Makes a GET request to the given path, timing out after the
		# given number of seconds, and calling the given block with a
		# hash containing :content, :headers, and :status, or just
		# false if there was an error.  The default category is the
		# path.
		def get path, category=nil, timeout=nil, &block
			# FIXME: Use em-http-request instead of HttpClient,
			# which returns an empty :content field for /description.xml
			request 'GET', path, category, nil, nil, timeout, &block
		end

		# Makes a POST request to the given path, with the given data
		# and content type, timing out after the given number of
		# seconds, and calling the given block with a hash containing
		# :content, :headers, and :status, or just false if there was
		# an error.  The default category is the path.
		def post path, data, category=nil, content_type=nil, timeout=nil, &block
			request 'POST', path, category, data, content_type, timeout, &block
		end

		# Makes a PUT request to the given path, with the given data
		# and content type, timing out after the given number of
		# seconds, and calling the given block with a hash containing
		# :content, :headers, and :status, or just false if there was
		# an error.
		def put path, data, category=nil, content_type=nil, timeout=nil, &block
			request 'PUT', path, category, data, content_type, timeout, &block
		end

		# Makes a DELETE request to the given path, timing out after
		# the given number of seconds, and calling the given block with
		# a hash containing :content, :headers, and :status, or just
		# false if there was an error.
		def delete path, category=nil, timeout=nil, &block
			request 'DELETE', path, category, nil, nil, timeout, &block
		end

		# Queues a request of the given type to the given path, using
		# the given data and content type for e.g. PUT and POST.  The
		# request will time out after timeout seconds.  The given block
		# will be called with a hash containing :content, :headers, and
		# :status if a response was received, or just false on error.
		# This should be called from the EventMachine reactor thread.
		def request verb, path, category=nil, data=nil, content_type=nil, timeout=nil, &block
			raise 'A block must be given.' unless block_given?
			raise 'Call from the EventMachine reactor thread.' unless EM.reactor_thread?

			category ||= path
			content_type ||= @default_type
			timeout ||= @default_timeout

			@request_queue[category] ||= []

			req = [verb, path, category, data, content_type, timeout, block]
			@request_queue[category] << req
			do_next_request category if @request_queue[category].size == 1
		end

		private
		# Sends a request with the given method/path/etc.  Called by
		# #do_next_request.  See #request.
		def do_request verb, path, category, data, content_type, timeout, &block
			req = EM::P::HttpClient.request(
				verb: verb,
				host: @host,
				request: path,
				content: data,
				contenttype: content_type,
			)
			req.callback {|response|
				begin
					yield response
				rescue => e
					log_e e, "Error calling a Hue bridge's request callback for #{category}."
				end

				@request_queue[category].shift
				do_next_request category
			}
			req.errback {
				req.close_connection # For timeout
				begin
					yield false
				rescue => e
					log_e e, "Error calling a Hue bridge's request callback with error for #{category}."
				end

				@request_queue[category].shift
				do_next_request category
			}
			req.timeout timeout
		end

		# Shifts a request off the request queue (if it is not empty),
		# then passes it to #do_request.  See #request.
		def do_next_request category
			unless @request_queue[category].empty?
				req = @request_queue[category].first
				block = req.pop
				do_request *req, &block
			end
		end
	end
end
