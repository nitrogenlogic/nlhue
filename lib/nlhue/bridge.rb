# A class representing a Hue bridge.
# (C)2014 Mike Bourgeous

require 'eventmachine'
require 'em/protocols/httpclient'
require 'rexml/document'
require 'json'

require_relative 'request_queue'

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
	# an actual Hue bridge if verify() hasn't succeeded.  Manages a list of
	# lights and groups on the bridge.  HTTP requests to the bridge are
	# queued and sent one at a time to prevent overloading the bridge's
	# CPU.
	class Bridge
		# Seconds to wait after an update round finishes before sending
		# more updates to lights and groups.
		RATE_LIMIT = 0.2

		attr_reader :username, :addr, :serial, :name

		@@bridge_cbs = [] # callbacks notified when a bridge has its first successful update

		# Adds a callback to be called with a Bridge object and a
		# status each time a Bridge has its first successful update,
		# adds or removes lights or groups, or becomes unregistered.
		# Bridge callbacks will be called after any corresponding :add
		# or :del disco event is delivered.  Returns a Proc object that
		# may be passed to remove_update_cb.
		#
		# Callback parameters:
		# Bridge first update:
		#	[Bridge], true
		#
		# Bridge added/removed lights or groups:
		#	[Bridge], true
		#
		# Bridge unregistered:
		#	[Bridge], false
		def self.add_bridge_callback &block
			@@bridge_cbs << block
			block
		end

		# Removes the given callback (returned by add_bridge_callback)
		# from Bridge first update/unregistration notifications.
		def self.remove_bridge_callback cb
			@@bridge_cbs.delete cb
		end

		# Sends the given bridge to all attached first update callbacks.
		def self.notify_bridge_callbacks br, status
			@@bridge_cbs.each do |cb|
				begin
					cb.call br, status
				rescue => e
					log_e e, "Error calling a first update callback"
				end
			end
		end

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
			@groups = {}
			@lightscan = {'lastscan' => 'none'}
			if serial && serial =~ /^[0-9A-Fa-f]{12}$/
				@serial = serial.downcase
			else
				@serial = nil
			end

			@request_queue = NLHue::RequestQueue.new addr, 2

			@update_timer = nil
			@update_callbacks = []

			@rate_timer = nil
			@rate_targets = {}
			@rate_proc = proc do
				if @rate_targets.empty?
					log "No targets, canceling rate timer." # XXX
					@rate_timer.cancel if @rate_timer
					@rate_timer = nil
				else
					log "Sending targets from rate timer." # XXX
					send_targets do
						@rate_timer = EM::Timer.new(RATE_LIMIT, @rate_proc)
					end
				end
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

			@request_queue.get '/description.xml', :info, 4 do |result|
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

					# FIXME: Delete this line when converted to em-http-request; this
					# works around the empty :content returned by EM::HttpClient
					#
					# See commits:
					# 34110773fc45bfdd56c32972650f9d947d8fac78
					# 6d8d7a0566e3c51c3ab15eb2358dde3e518594d3
					@verified = true
				end

				begin
					yield @verified
				rescue => e
					log_e e, "Error notifying block after verification"
				end
			end
		end

		# Attempts to register the given username with the Bridge.  The
		# block will be called with true and the result if registration
		# succeeds, false and an exception if not.  If registration
		# succeeds, the Bridge's current username will be set to the
		# given username.  If the username is the current username
		# assigned to this Bridge object, and it already appears to be
		# registered, it will not be re-registered, and the block will
		# be called with true and a message.  Call #update after
		# registration succeeds.  #registered? will not return true
		# until #update has succeeded.
		def register username, devicetype, &block
			raise NotVerifiedError.new unless @verified
			check_username username

			if username == @username && @registered
				yield true, 'Already registered.'
				return
			end

			msg = %Q{{"username":#{username.to_json},"devicetype":#{devicetype.to_json}}}
			@request_queue.post '/api', msg, :registration, nil, 6 do |response|
				status, result = check_json response

				if status
					@username = username
				end

				yield status, result
			end
		end

		# Deletes the given username from the Bridge's whitelist.
		def unregister username, &block
			raise NotVerifiedError.new unless @verified
			check_username username

			@request_queue.delete "/api/#{username}/config/whitelist/#{username}", :registration, 6 do |response|
				status, result = check_json response

				if @username == username && status
					@registered = false
					Bridge.notify_bridge_callbacks self, false
				end

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
		# received, or when a subscription update fails.  The return
		# value may be passed to remove_update_callback.
		#
		# Callback parameters:
		# Update successful:
		# 	true, [lights or groups changed: true/false]
		#
		# Update failed:
		# 	false, [exception]
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
		# of the Hue bridge.  Also updates the current light scan
		# status on the first update or if the Bridge thinks a scan is
		# currently active.  On success the given block will be called
		# with true and whether the lights/groups were changed, false
		# and an exception on error.
		def update &block
			@request_queue.get "/api/#{@username}", :info do |response|
				status, result = check_json response

				changed = false

				begin
					if status
						first_update = !@registered

						@config = result
						@config['lights'].each do |id, info|
							id = id.to_i
							if @lights[id].is_a? Light
								@lights[id].handle_json info
							else
								@lights[id] = Light.new(self, id, info)
								changed = true
							end
						end
						@lights.select! do |id, light|
							incl = @config['lights'].include? id.to_s
							changed ||= !incl
							incl
						end

						set_name @config['config']['name'] unless @name
						@serial ||= @config['config']['mac'].gsub(':', '').downcase

						@registered = true

						unless @groups[0].is_a? Group
							get_api '/groups/0', :info do |response|
								status, result = check_json response
								if status
									if @groups[0].is_a? Group
										@groups[0].handle_json result
									else
										@groups[0] = Group.new(self, 0, result)
										notify_update_callbacks true, true
										Bridge.notify_bridge_callbacks self, true
									end
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
								changed = true
							end
						end
						@groups.select! do |id, light|
							incl = @config['groups'].include?(id.to_s) || id == 0
							changed ||= !incl
							incl
						end

						# TODO: schedules

						scan_status true if first_update || @lightscan['lastscan'] == 'active'

						Bridge.notify_bridge_callbacks self, true if first_update || changed
					end
				rescue => e
					log_e e, "Bridge #{@serial} update raised an exception"
					status = false
					result = e
				end

				result = changed if status
				notify_update_callbacks status, result

				yield status, result
			end
		end

		# Initiates a scan for new lights.  If a block is given, yields
		# true if the scan was started, an exception if there was an
		# error.
		def scan_lights &block
			post_api '/lights', nil do |response|
				begin
					status, result = check_json response
					@lightscan['lastscan'] = 'active' if status
					yield status if block_given?
				rescue => e
					yield e
				end
			end
		end

		# Calls the given block (if given) with true and the last known
		# light scan status from the bridge.  Requests the current scan
		# status from the bridge if request is true.  The block will be
		# called with false and an exception if an error occurs during
		# a request.  Returns the last known scan status.
		#
		# The scan status is a Hash with the following form:
		# {
		#	'1' => { 'name' => 'New Light 1' }, # If new lights were found
		#	'2' => { 'name' => 'New Light 2' },
		#	'lastscan' => 'active'/'none'/ISO8601:2004
		# }
		def scan_status request=false, &block
			if request
				# TODO: Update group 0 if new lights are found or when a scan completes
				get_api '/lights/new' do |response|
					begin
						status, result = check_json response
						@lightscan = result if status
						yield status, result if block_given?
					rescue => e
						yield e
					end
				end
			else
				yield true, @lightscan if block_given?
			end

			@lightscan unless block_given?
		end

		# Returns true if a scan for lights is active (as of the last
		# call to #update), false otherwise.
		def scan_active?
			@lightscan['lastscan'] == 'active'
		end

		# Returns whether the Bridge object has had at least one
		# successful update from #update.
		def updated?
			@config.is_a? Hash
		end

		# Indicates whether verification succeeded.  A Hue bridge has
		# been verified to exist at the address given to the
		# constructor or to #addr= if this returns true.  Use #verify
		# to perform verification if this returns false.
		def verified?
			@verified
		end

		# Returns true if this bridge is subscribed (i.e. periodically
		# polling the Hue bridge for updates).
		def subscribed?
			!!@update_timer
		end

		# Returns whether the Bridge object believes it is registered
		# with its associated Hue bridge.  Set to true when #update
		# or #register succeeds, false if a NotRegisteredError occurs.
		def registered?
			@registered
		end

		# Returns a Hash mapping light IDs to Light objects,
		# representing the lights known to the Hue bridge.
		def lights
			@lights.clone
		end

		# The number of lights known to this bridge.
		def num_lights
			@lights.length
		end

		# Returns a Hash mapping group IDs to Group objects
		# representing the groups known to this bridge, including the
		# default group 0 that contains all lights from this bridge.
		def groups
			@groups.clone
		end

		# The number of groups known to this bridge, including the
		# default group that contains all lights known to the bridge.
		def num_groups
			@groups.length
		end

		# Creates a new group with the given name and list of lights.
		# The given block will be called with true and a NLHue::Group
		# object on success, false and an error on failure.
		def create_group name, lights, &block
			raise "No group name was given" unless name.is_a?(String) && name.length > 0
			raise "No lights were given" unless lights.is_a?(Array) && lights.length > 0

			light_ids = []
			lights.each do |l|
				raise "All given lights must be NLHue::Light objects" unless l.is_a?(NLHue::Light)
				raise "Light #{l.id} (#{l.name}) is not from this bridge." if l.bridge != self

				light_ids << l.id
			end

			group_data = { :lights => light_ids, :name => name }.to_json
			post_api '/groups', group_data, :lights do |response|
				puts "\n\n\n#{response.inspect}\n\n\n" # XXX
				yield true, response # XXX
			end
		end

		# Deletes the given NLHue::Group on this bridge.  Raises an
		# exception if the group is group 0.  Calls the given block
		# with true and a message on success, or false and an error on
		# failure.
		def delete_group group, &block
			raise "No group was given to delete" if group.nil?
			raise "Group must be a NLHue::Group object" unless group.is_a?(NLHue::Group)
			raise "Group is not from this bridge" unless group.bridge == self
			raise "Cannot delete group 0" if group.id == 0

			# TODO: delete_api
			raise NotImplementedError 'Group deletion is not implemented.'
		end

		# Sets the username used to interact with the bridge.
		def username= username
			check_username username
			@username = username
		end

		# Sets the IP address or hostname of the Hue bridge.  The
		# Bridge object will be marked as unverified, so #verify should
		# be called afterward.
		def addr= addr
			@addr = addr
			@verified = false
			@request_queue.addr = addr
		end

		# Unsubscribes from bridge updates, marks this bridge as
		# unregistered, notifies global bridge callbacks added with
		# add_bridge_callback, then removes references to
		# configuration, lights, groups, and update callbacks.
		def clean
			was_updated = updated?
			unsubscribe
			@registered = false

			Bridge.notify_bridge_callbacks self, false if was_updated

			@verified = false
			@config = nil
			@lights.clear
			@groups.clear
			@update_callbacks.clear
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
							was_reg = @registered
							@registered = false
							Bridge.notify_bridge_callbacks self, false if was_reg

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
			str = "Hue Bridge: #{@addr}: #{@name} (#{@serial}) - #{@lights.length} lights"
			str << " (#{registered? ? '' : 'un'}registered)"
			str
		end

		# Returns a Hash with information about this bridge:
		# {
		# 	:addr => "[IP address]",
		# 	:name => "[name]",
		# 	:serial => "[serial number]",
		# 	:registered => true/false,
		# 	:scan => [return value of #scan_status],
		# 	:lights => [hash containing Light objects (see #lights)],
		# 	:groups => [hash containing Group objects (see #groups)],
		# 	:config => [raw config from bridge] if include_config
		# }
		#
		# Do not modify the included lights and groups hashes.
		def to_h include_config=false
			h = {
				:addr => @addr,
				:name => @name,
				:serial => @serial,
				:registered => @registered,
				:scan => @lightscan,
				:lights => @lights,
				:groups => @groups
			}
			h[:config] = @config if include_config
			h
		end

		# Return value of to_h converted to a JSON string.
		# Options: :include_config => true -- include raw config returned by the bridge
		def to_json *args
			to_h(args[0].is_a?(Hash) && args[0][:include_config]).to_json(*args)
		end

		# Makes a GET request under the API using this Bridge's stored
		# username.
		def get_api subpath, category=nil, &block
			@request_queue.get "/api/#{@username}#{subpath}", &block
		end

		# Makes a POST request under the API using this Bridge's stored
		# username.
		def post_api subpath, data, category=nil, content_type=nil, &block
			@request_queue.post "/api/#{@username}#{subpath}", data, category, content_type, &block
		end

		# Makes a PUT request under the API using this Bridge's stored
		# username.
		def put_api subpath, data, category=nil, content_type=nil, &block
			@request_queue.put "/api/#{@username}#{subpath}", data, category, content_type, &block
		end

		# Schedules a Light or Group to have its deferred values sent
		# the next time the rate limiting timer fires, or immediately
		# if the rate limiting timer has expired.  Starts the rate
		# limiting timer if it is not running.
		def add_target t, &block
			raise 'Target must be a Light or a Group' unless t.is_a?(Light) || t.is_a?(Group)
			raise "Target is from #{t.bridge.serial} not this bridge (#{@serial})" unless t.bridge == self

			log "Adding deferred target #{t}" # XXX

			@rate_targets[t] ||= []
			@rate_targets[t] << block if block_given?

			unless @rate_timer
				log "No rate timer -- sending targets on next tick" # XXX

				# Waiting until the next tick allows multiple
				# updates to be queued in the current tick that
				# will all go out at the same time.
				EM.next_tick do
					log "It's next tick -- sending targets now" # XXX
					send_targets
				end

				log "Setting rate timer"
				@rate_timer = EM::Timer.new(RATE_LIMIT, @rate_proc)
			else
				log "Rate timer is set -- not sending targets now" # XXX
			end
		end

		private
		# Sets this bridge's name (call after getting UPnP XML or
		# bridge config JSON), removing the IP address if present.
		def set_name name
			@name = name.gsub " (#{@addr})", ''
		end

		# Calls #send_changes on all targets in the rate-limiting
		# queue, passing the result to each callback that was scheduled
		# by a call to #submit on the Light or Group.  Clears the
		# rate-limiting queue.  Calls the block (if given) with no
		# arguments once all changes scheduled at the time of the
		# initial call to send_targets have been sent.
		def send_targets &block
			targets = @rate_targets.to_a
			@rate_targets.clear

			return if targets.empty?

			target, cbs = targets.shift

			target_cb = proc {|status, result|

				cbs.each do |cb|
					begin
						cb.call status, result if cb
					rescue => e
						log_e e, "Error notifying rate limited target #{t} callback #{cb.inspect}"
					end
				end

				target, cbs = targets.shift

				if target
					log "Sending subsequent target #{target}" # XXX
					target.send_changes &target_cb
				else
					yield if block_given?
				end
			}

			log "Sending first target #{target}" # XXX
			target.send_changes &target_cb
		end

		# Calls all callbacks added using #add_update_callback with the
		# given update status and result.
		def notify_update_callbacks status, result
			@update_callbacks.each do |cb|
				begin
					cb.call status, result
				rescue => e
					log_e e, "Error calling an update callback"
				end
			end
		end
	end
end
