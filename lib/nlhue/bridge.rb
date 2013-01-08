# A class representing a Hue bridge.
# (C)2012 Mike Bourgeous

require 'eventmachine'
require 'em/protocols/httpclient'
require 'rexml/document'
require 'json'

module NLHue
	class NotVerifiedError < StandardError
		def initialize msg="Call .verify() before using the bridge."
			super msg
		end
	end

	class LinkButtonError < StandardError
		def initialize msg="Press the bridge's link button."
			super msg
		end
	end

	class NotRegisteredError < StandardError
		def initialize msg="Press the bridge's link button and call .register()."
			super msg
		end
	end

	# A class representing a Hue bridge.  A Bridge object may not refer to
	# an actual Hue bridge if verify() hasn't succeeded.
	class Bridge
		attr_reader :username, :addr, :serial, :name

		# addr - The IP address or hostname of the Hue bridge.
		# serial - The serial number of the bridge, if available
		# 	   (parsed from the USN header in a UPnP response)
		def initialize addr, serial = nil
			@addr = addr
			@verified = false
			@username = 'invalid'
			@name = nil
			@config = nil
			@registered = false
			@lights = {}
			if serial && serial =~ /^[0-9A-Fa-f]{12}$/
				@serial = serial.downcase
			else
				@serial = nil
			end
		end

		# Calls the given block with true or false if verification by
		# description.xml succeeds or fails.  If verification has
		# already been performed, the block will be called immediately
		# with true.
		def verify &block
			if @verified
				yield true
				return true
			end

			get '/description.xml' do |result|
				puts "Description result: #{result.inspect}" # XXX
				if result.is_a?(Hash) && result[:status] == 200
					@desc = REXML::Document.new result[:content]
					@desc.write($stdout, 4, true) # XXX
					@desc.elements.each('friendlyName') do |el|
						puts "Friendly name: #{@name}" # XXX
						set_name el.text
					end
					@desc.elements.each('serialNumber') do |el|
						puts "Serial number: #{@serial}" # XXX
						@serial = el.text.downcase
					end
					@desc.elements.each('modelName') do |el|
						puts "modelName: #{el.text}" # XXX
						if el.text.include? 'Philips hue'
							@verified = true
						end
					end
				end

				# XXX yield @verified
				@verified = true
				begin
					yield true
				rescue => e
					# TODO: Use a user-provided logging facility?
					puts "Error notifying block after verification: #{e}", e.backtrace
				end
			end
		end

		# Attempts to register the given username with the Bridge.  The
		# block will be called with true and the result if registration
		# succeeds, false and an exception if not.
		def register username, devicetype, &block
			raise NotVerifiedError.new unless @verified
			check_username username

			msg = %Q{{"username":#{username.to_json},"devicetype":#{devicetype.to_json}}}
			puts "Sending #{msg}" # XXX
			post '/api', msg do |response|
				puts "Register response: #{response.inspect}" # XXX

				status = true
				result = response

				begin
					result = check_json response
				rescue => e
					status = false
					result = e
				end

				@username = username if status
				yield status, result
			end
		end

		# Deletes the given username from the Bridge's whitelist.
		def unregister username, &block
			raise NotVerifiedError.new unless @verified
			check_username username

			delete "/api/#{username}/config/whitelist/#{username}" do |response|
				puts "Unregister response: #{response.inspect}" # XXX

				status = true
				result = response

				begin
					result = check_json response
				rescue => e
					status = false
					result = e
				end

				@registered = false if @username == username && status

				yield status, result
			end
		end

		# Updates the Bridge object with the lights, groups, and config
		# of the Hue bridge.  The given block will be called with true
		# and the result on success, false and an exception on error.
		def update &block
			get "/api/#{@username}" do |response|
				status = true
				result = response

				begin
					result = check_json response
					puts 'after check_json'
					@config = result
					@config['lights'].each do |id, info|
						puts "Checking light #{id}, #{info}" # XXX
						if @lights[id.to_i].is_a? Light
							@lights[id.to_i].handle_json info
						else
							@lights[id.to_i] = Light.new(self, id, info)
						end
					end
					puts 'after lights'
					@lights.select do |id, light|
						incl = @config['lights'].include? id.to_s
						puts "Including light ID #{id}: #{incl}" # XXX
						incl
					end
					puts 'after old lights'

					set_name @config['config']['name'] unless @name
					@serial ||= @config['config']['mac'].gsub(':', '').downcase

					@registered = true

					# TODO: Groups, schedules
				rescue => e
					status = false
					result = e
				end

				yield status, result
			end
		end

		def updated?
			@config.is_a? Hash
		end

		# Returns whether the Bridge object believes it is registered
		# with its associated Hue bridge.  Set to true when update
		# succeeds, set to false if a NotRegisteredError occurs.
		def registered?
			@registered
		end

		# Returns an array of Light objects representing the lights
		# known to the Hue bridge.
		def lights
			@lights
		end

		# The number of lights known to this bridge.
		def num_lights
			@lights.length
		end

		# Sets the username used to interact with the bridge.
		def username= username
			check_username username
			@username = username
		end

		# Throws errors if the given username is invalid (may not catch
		# all invalid names).
		def check_username username
			raise 'Username must be >= 10 characters.' unless username.to_s.length >= 10
			raise 'Spaces are not permitted in usernames.' if username =~ /[[:space:]]/
		end

		# Checks for a valid JSON-containing response from an HTTP
		# request method, raises an error if invalid or no response.
		# Does not consider non-200 HTTP response codes as errors.
		# Returns the received JSON if no error occurred.  Marks this
		# bridge as not registered if there is a NotRegisteredError.
		def check_json response
			raise 'No response received.' if response == false

			j = nil
			if response.is_a?(Hash)
				status = true
				result_msgs = []

				j = JSON.parse response[:content]
				if j.is_a? Array
					j.each do |v|
						if v.is_a?(Hash) && v['error'].is_a?(Hash); then
							status = false
							result_msgs << v['error']['description']
						end
					end
				end

				unless status
					if result_msgs.include?('link button not pressed')
						raise LinkButtonError.new
					elsif result_msgs.include?('unauthorized user')
						@registered = false
						raise NotRegisteredError.new
					else
						raise StandardError.new(result_msgs.join(', '))
					end
				end
			end

			return j
		end

		# "Hue Bridge: [IP]: [Friendly Name] ([serial]) - N lights"
		def to_s
			"Hue Bridge: #{@addr}: #{@name} (#{@serial}) - #{@lights.length} lights"
		end

		# JSON object with "addr": [bridge address] and "config":
		# [config JSON from bridge]
		def to_json
			{ :addr => @addr, :name => @name, :serial => @serial, :config => @config }.to_json
		end

		# Makes a GET request to the given path, timing out after the
		# given number of seconds, and calling the given block with a
		# hash containing :content, :headers, and :status, or just
		# false if there was an error.
		def get path, timeout=5, &block
			# FIXME: Use em-http-request instead of HttpClient,
			# which returns an empty :content field
			request 'GET', path, nil, nil, timeout, &block
		end

		# Makes a GET request under the API using this Bridge's stored
		# username.
		def get_api subpath, &block
			get "/api/#{@username}#{subpath}", &block
		end

		# Makes a POST request to the given path, with the given data
		# and content type, timing out after the given number of
		# seconds, and calling the given block with a hash containing
		# :content, :headers, and :status, or just false if there was
		# an error.
		def post path, data, content_type='application/json;charset=utf-8', timeout=5, &block
			request 'POST', path, data, content_type, timeout, &block
		end

		# Makes a PUT request to the given path, with the given data
		# and content type, timing out after the given number of
		# seconds, and calling the given block with a hash containing
		# :content, :headers, and :status, or just false if there was
		# an error.
		def put path, data, content_type='application/json;charset=utf-8', timeout=5, &block
			request 'PUT', path, data, content_type, timeout, &block
		end

		# Makes a PUT request under the API using this Bridge's stored
		# username.
		def put_api subpath, data, content_type='application/json;charset=utf-8', &block
			put "/api/#{@username}#{subpath}", data, content_type, &block
		end

		# Makes a DELETE request to the given path, timing out after
		# the given number of seconds, and calling the given block with
		# a hash containing :content, :headers, and :status, or just
		# false if there was an error.
		def delete path, timeout=5, &block
			request 'DELETE', path, nil, nil, timeout, &block
		end

		# Makes a request of the given type to the given path, using
		# the given data and content type for e.g. PUT and POST.  The
		# request will time out after timeout seconds.  The given block
		# will be called with a hash containing :content, :headers, and
		# :status if a response was received, or just false on error.
		def request verb, path, data=nil, content_type='application/json;charset=utf-8', timeout=5, &block
			raise 'A block must be given.' unless block_given?
			req = EM::P::HttpClient.request(
				verb: verb,
				host: @addr,
				request: path,
				content: data,
				contenttype: content_type,
			)
			req.callback {|response|
				yield response
			}
			req.errback {
				req.close_connection # For timeout
				yield false
			}
			req.timeout 5
		end

		private
		# Sets this bridge's name (call after getting UPnP XML or
		# bridge config JSON), removing the IP address if present.
		def set_name name
			@name = name.gsub " (#{@addr})", ''
		end
	end
end
