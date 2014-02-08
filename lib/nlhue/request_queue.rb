# A class for managing HTTP requests to a host.  Only allows one outstanding
# request to a given category, while allowing requests to unrelated categories.
# Categories default to path names.
# (C)2013 Mike Bourgeous

require 'eventmachine'
require 'em/protocols/httpclient'

module NLHue
	class RequestQueue
		@@logging = ENV['NLHUE_LOG'] == 'true'
		@@logging_target = nil
		@@logging_proc = nil

		@@next_id = 0
		@@id_lock = Mutex.new

		# Enables/disables detailed logging for RequestQueues.  If a
		# block is specified, the block will be called with log
		# messages.  The default target is STDOUT.  If target is nil
		# and a block is given,  messages will not be written to the
		# target.  Errors may still be logged to STDERR separately from
		# this mechanism.
		def self.enable_logging enabled, target=nil, &block
			raise 'Logging target must respond to :puts.' if target && !target.respond_to?(:puts)
			@@logging = !!enabled
			@@logging_target = target
			@@logging_proc = block
		end

		# Returns true if detailed logging is enabled for RequestQueue.
		def self.logging_enabled?
			@@logging
		end

		attr_reader :host

		# Initializes a request queue with the given host, default
		# request timeout, and default POST/PUT content type.
		def initialize host, timeout, content_type='application/json;charset=utf-8'
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

			req = [verb, path, category, data, content_type, timeout, block, RequestQueue.next_id]
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

		# Logs the given message to the logging target and/or logging proc specified with logging=
		def self.log_msg msg
			if !@@logging_target.nil? || (@@logging_target.nil? && @@logging_proc.nil?)
				(@@logging_target || STDOUT).puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S.%6N %z')} - #{msg}"
			end

			@@logging_proc.call msg if @@loging_proc
		end

		# Indicates that the given request has been queued.
		def self.log_queued req
			log_msg "Request queued: TODO"
		end

		# Indicates that the given request has been submitted.
		def self.log_start req
			log_msg "Request started: TODO"
		end

		# Returns a unique ID for a request.
		def self.next_id
			@@id_lock.synchronize {
				@@next_id += 1
				return @@next_id
			}
		end
	end
end
