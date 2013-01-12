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
			@groups = []
			if serial && serial =~ /^[0-9A-Fa-f]{12}$/
				@serial = serial.downcase
			else
				@serial = nil
			end

			@update_timer = nil
			@update_callbacks = []
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
		# succeeds, false and an exception if not.  If the username is
		# the current username assigned to this Bridge object, and it
		# already appears to be registered, it will not be
		# re-registered, and the block will be called with true and a
		# message.
		def register username, devicetype, &block
			raise NotVerifiedError.new unless @verified
			check_username username

			if username == @username && @registered
				yield true, 'Already registered.'
				return
			end

			msg = %Q{{"username":#{username.to_json},"devicetype":#{devicetype.to_json}}}
			post '/api', msg do |response|
				status, result = check_json response

				@username = username if status

				yield status, result
			end
		end

		# Deletes the given username from the Bridge's whitelist.
		def unregister username, &block
			raise NotVerifiedError.new unless @verified
			check_username username

			delete "/api/#{username}/config/whitelist/#{username}" do |response|
				status, result = check_json response

				@registered = false if @username == username && status

				yield status, result
			end
		end

		# Starts a timer that retrieves the current state of the bridge
		# every interval seconds.  Does nothing if this Bridge is
		# already subscribed.
		def subscribe interval=1
			return if @update_timer

			update_proc = proc {
				update do |status, result|
					@update_callbacks.each do |cb|
						begin
							cb.call status, result
						rescue => e
							puts "Error calling an update callback: #{e}", e.backtrace
						end
					end
					@update_timer = EM::Timer.new(interval, update_proc) if @update_timer
				end
			}

			@update_timer = EM::Timer.new(interval, update_proc)
		end

		# Stops the timer started by subscribe(), if one is running.
		def unsubscribe
			@update_timer.cancel if @update_timer
			@update_timer = nil
		end

		# Adds a callback to be notified when a subscription update is
		# received, or when a subscription update fails.  The callback
		# will be called with true and the update JSON when an update
		# succeeds, false and the update JSON when an update fails.
		# The return value may be passed to remove_update_callback.
		def add_update_callback &cb
			@update_callbacks << cb
			cb
		end

		# Removes the given callback (returned by add_update_callback)
		# from the list of callbacks notified with subscription events.
		def remove_update_callback cb
			@update_callbacks.delete cb
		end

		# Updates the Bridge object with the lights, groups, and config
		# of the Hue bridge.  The given block will be called with true
		# and the result on success, false and an exception on error.
		def update &block
			get "/api/#{@username}" do |response|
				status, result = check_json response

				begin
					if status
						@config = result
						@config['lights'].each do |id, info|
							id = id.to_i
							if @lights[id].is_a? Light
								@lights[id].handle_json info
							else
								@lights[id] = Light.new(self, id, info)
							end
						end
						@lights.select do |id, light|
							incl = @config['lights'].include? id.to_s
							incl
						end

						set_name @config['config']['name'] unless @name
						@serial ||= @config['config']['mac'].gsub(':', '').downcase

						@registered = true

						get_api '/groups/0' do |response|
							status, result = check_json response
							if status
								if @groups[0].is_a? Group
									@groups[0].handle_json result
								else
									@groups[0] = Group.new(self, 0, result)
								end
							end
						end

						@config['groups'].each do |id, info|
							# With no idea what the group configuration
							# will look like at this point, I'm guessing
							# that it is similar to the lights.
							# TODO: Test with actual groups
							if @groups[id.to_i].is_a? Group
								@groups[id.to_i].handle_json info
							else
								@groups[id.to_i] = Group.new(self, id.to_i, info)
							end
						end
						@groups.select do |id, light|
							@config['groups'].include? id.to_s
						end

						# TODO: schedules
					end
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
			@lights.values
		end

		# The number of lights known to this bridge.
		def num_lights
			@lights.length
		end

		# Returns an array of Group objects representing the groups
		# known to this bridge, including the default group that
		# contains all lights known to this bridge.
		def groups
			@groups.clone
		end

		# The number of groups known to this bridge, including the
		# default group that contains all lights known to the bridge.
		def num_groups
			@groups.length
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
		# request method, returns an error if invalid or no response.
		# Does not consider non-200 HTTP response codes as errors.
		# Returns true and the received JSON if no error occurred, or
		# false and an exception if an error did occur.  Marks this
		# bridge as not registered if there is a NotRegisteredError.
		def check_json response
			status = false
			result = nil

			begin
				raise 'No response received.' if response == false

				if response.is_a?(Hash)
					status = true
					result_msgs = []

					result = JSON.parse response[:content]
					if result.is_a? Array
						result.each do |v|
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
			rescue => e
				status = false
				result = e
			end

			return status, result
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
