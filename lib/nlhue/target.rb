# Base class representing a light or group known to a Hue bridge.
# (C)2015 Mike Bourgeous

module NLHue
	# Base class representing a light or group known to a Hue bridge.  See
	# NLHue::Light and NLHue::Group.
	class Target
		attr_reader :id, :type, :name, :bridge, :transitiontime

		# bridge - The Bridge that controls this light or group.
		# id - The light or group's ID (>=0 for groups, >=1 for lights).
		# info - Parsed Hash of the JSON light or group info object from the bridge.
		# api_category - The category to pass to the bridge for rate limiting API
		# 		 requests.  Also forms part of the API URL.
		# api_target - @api_target for lights, @api_target for groups
		def initialize(bridge, id, info, api_category, api_target)
			@bridge = bridge
			@id = id.to_i
			@api_category = api_category
			@api_target = api_target

			@changes = Set.new
			@defer = false

			@info = {api_target => {}}
			handle_json(info || {})
		end

		# Updates this light or group object using a Hash parsed from
		# the JSON info from the Hue bridge.
		def handle_json(info)
			raise "Light/group info must be a Hash, not #{info.class}." unless info.is_a?(Hash)

			# A group contains no 'xy' for a short time after creation.
			# Add fake xy color for lamps that don't support color.
			info[@api_target] = {} unless info[@api_target].is_a?(Hash)
			info[@api_target]['xy'] ||= [0.33333, 0.33333]

			info['id'] = @id

			# Preserve deferred changes that have not yet been sent to the bridge
			@changes.each do |key|
				info[@api_target][key] = @info[@api_target][key]
			end

			@info = info
			@type = @info['type']
			@name = @info['name'] || @name || "Lightset #{@id}"
		end

		# Gets the current state of this light or group from the
		# bridge.  The block, if given, will be called with true and
		# the response on success, or false and an Exception on error.
		def update(&block)
			tx = rand
			@bridge.get_api "/#{@api_category}/#{@id}", @api_category do |response|
				puts "#{tx} Target #{@id} update response: #{response}" # XXX

				begin
					status, result = @bridge.check_json(response)
					handle_json(result) if status
				rescue => e
					status = false
					result = e
				end

				yield status, result if block_given?
			end
		end

		# Returns a copy of the hash representing the light or group's
		# state as parsed from the JSON returned by the bridge, without
		# any range scaling (e.g. so hue range is 0..65535).
		def to_h
			@info.clone
		end

		# Converts the Hash returned by #state to JSON.
		def to_json(*args)
			state.to_json(*args)
		end

		# Call to queue changes to be sent all at once.  Updates will
		# not be sent to the light or group until #submit is called.
		# Call #nodefer to stop deferring changes.
		def defer
			@defer = true
		end

		# Stops deferring changes and sends any queued changes
		# immediately.
		def nodefer
			@defer = false
			set {}
		end

		# Sets the transition time in centiseconds used for the next
		# immediate parameter change or deferred batch parameter
		# change.  The transition time will be reset when send_changes
		# is called.  Call with nil to clear the transition time.
		def transitiontime=(time)
			if time.nil?
				@transitiontime = nil
			else
				time = 0 if time < 0
				@transitiontime = time.to_i
			end
		end

		# Tells the Bridge object that this Light or Group is ready to
		# have its deferred data sent.  The NLHue::Bridge will schedule
		# a rate-limited call to #send_changes, which sends all changes
		# queued since the last call to defer.  The block, if given,
		# will be called with true and the response on success, or
		# false and an Exception on error.  The transition time sent to
		# the bridge can be controlled with transitiontime=.  If no
		# transition time is set, the default transition time will be
		# used by the bridge.
		def submit(&block)
			puts "Submitting changes to #{self}" # XXX
			@bridge.add_target self, &block
		end

		# Returns a Hash containing the light's info and current state,
		# with symbolized key names and hue scaled to 0..360.  Example:
		# {
		#    :id => 1,
		#    :name => 'Hue Lamp 2',
		#    :type => 'Extended color light',
		#    :on => false,
		#    :bri => 220,
		#    :ct => 500,
		#    :x => 0.5,
		#    :y => 0.5,
		#    :hue => 193.5,
		#    :sat => 255,
		#    :colormode => 'hs'
		# }
		def state
			{
				:id => id,
				:name => name,
				:type => type,
				:on => on?,
				:bri => bri,
				:ct => ct,
				:x => x,
				:y => y,
				:hue => hue,
				:sat => sat,
				:colormode => colormode
			}
		end

		# Tells the light or group to flash once if repeat is false, or
		# several times if repeat is true.  Sets the 'alert' property.
		def alert!(repeat=false)
			set({ 'alert' => repeat ? 'select' : 'lselect' })
		end

		# Stops any existing flashing of the light or group.
		def clear_alert
			set({ 'alert' => 'none' })
		end

		# Sets the light or group's alert status to the given string
		# (one of 'select' (flash once), 'lselect' (flash several
		# times), or 'none' (stop flashing)).  Any other value may
		# result in an error from the bridge.
		def alert=(alert)
			set({ 'alert' => alert })
		end

		# Returns the current alert state of the light or group (or the
		# stored state if defer() was called, but send() has not yet
		# been called).  Groups are not updated when their constituent
		# lights are changed individually.
		def alert
			(@info[@api_target] || @info[@api_target])['alert']
		end

		# Sets the on/off state of this light or group (true or false).
		# Lights must be on before other parameters can be changed.
		def on=(on)
			set({ 'on' => !!on })
		end

		# The light state most recently set with on=, #on! or #off!, or
		# the last light state received from the bridge due to calling
		# #update on the light/group or on the NLHue::Bridge.
		def on?
			@info[@api_target]['on']
		end

		# Turns the light or group on.
		def on!
			self.on = true
		end

		# Turns the light or group off.
		def off!
			self.on = false
		end

		# Sets the brightness of this light or group (0-255 inclusive).
		# Note that a brightness of 0 is not off.  The light(s) must
		# already be switched on for this to work, if not deferred.
		def bri=(bri)
			bri = 0 if bri < 0
			bri = 255 if bri > 255

			set({ 'bri' => bri.to_i })
		end

		# The brightness most recently set with #bri=, or the last
		# brightness received from the light or group due to calling
		# #update on the target or on the bridge.
		def bri
			# TODO: Field storing @api_target or @api_target
			@info[@api_target]['bri'].to_i
		end

		# Switches the light or group into color temperature mode and
		# sets the color temperature of the light in mireds (154-500
		# inclusive, where 154 is highest temperature (bluer), 500 is
		# lowest temperature (yellower)).  The light(s) must be on for
		# this to work, if not deferred.
		def ct=(ct)
			ct = 154 if ct < 154
			ct = 500 if ct > 500

			set({ 'ct' => ct.to_i, 'colormode' => 'ct' })
		end

		# The color temperature most recently set with ct=, or the last
		# color temperature received from the light due to calling
		# #update on the light or on the bridge.
		def ct
			@info[@api_target]['ct'].to_i
		end

		# Switches the light or group into CIE XYZ color mode and sets
		# the X color coordinate to the given floating point value
		# between 0 and 1, inclusive.  Lights must be on for this to
		# work.
		def x=(x)
			self.xy = [ x, @info[@api_target]['xy'][1] ]
		end

		# The X color coordinate most recently set with #x= or #xy=, or
		# the last X color coordinate received from the light or group.
		def x
			@info[@api_target]['xy'][0].to_f
		end

		# Switches the light or group into CIE XYZ color mode and sets
		# the Y color coordinate to the given floating point value
		# between 0 and 1, inclusive.  Lights must be on for this to
		# work.
		def y=(y)
			self.xy = [ @info[@api_target]['xy'][0], y ]
		end

		# The Y color coordinate most recently set with #y= or #xy=, or
		# the last Y color coordinate received from the light or group.
		def y
			@info[@api_target]['xy'][1].to_f
		end

		# Switches the light or group into CIE XYZ color mode and sets
		# the XY color coordinates to the given two-element array of
		# floating point values between 0 and 1, inclusive.  Lights
		# must be on for this to work, if not deferred.
		def xy=(xy)
			unless xy.is_a?(Array) && xy.length == 2 && xy[0].is_a?(Numeric) && xy[1].is_a?(Numeric)
				raise 'Pass a two-element array of numbers to xy=.'
			end

			xy[0] = 0 if xy[0] < 0
			xy[0] = 1 if xy[0] > 1
			xy[1] = 0 if xy[1] < 0
			xy[1] = 1 if xy[1] > 1

			set({ 'xy' => xy, 'colormode' => 'xy' })
		end

		# The XY color coordinates most recently set with #x=, #y=, or
		# #xy=, or the last color coordinates received from the light
		# or group due to calling #update on the target or the bridge.
		def xy
			xy = @info[@api_target]['xy']
			[ xy[0].to_f, xy[1].to_f ]
		end

		# Switches the light or group into hue/saturation mode and sets
		# the hue to the given value (floating point degrees, wrapped
		# to 0-360).  The light(s) must already be on for this to work.
		def hue=(hue)
			hue = (hue * 65536 / 360).to_i & 65535
			set({ 'hue' => hue, 'colormode' => 'hs' })
		end

		# The hue most recently set with #hue=, or the last hue
		# received from the light or group due to calling #update on
		# the target or on the bridge.
		def hue
			@info[@api_target]['hue'].to_i * 360 / 65536.0
		end

		# Switches the light into hue/saturation mode and sets the
		# light's saturation to the given value (0-255 inclusive).
		def sat=(sat)
			sat = 0 if sat < 0
			sat = 255 if sat > 255

			set({ 'sat' => sat.to_i, 'colormode' => 'hs' })
		end

		# The saturation most recently set with #saturation=, or the
		# last saturation received from the light due to calling
		# #update on the light or on the bridge.
		def sat
			@info[@api_target]['sat'].to_i
		end

		# Sets the light or group's special effect mode (either 'none'
		# or 'colorloop').
		def effect= effect
			effect = 'none' unless effect == 'colorloop'
			set({ 'effect' => effect })
		end

		# The light or group's last set special effect mode.
		def effect
			@info[@api_target]['effect']
		end

		# Returns the light or group's current or last set color mode
		# ('ct' for color temperature, 'hs' for hue/saturation, 'xy'
		# for CIE XYZ).
		def colormode
			@info[@api_target]['colormode']
		end

		# Sends parameters named in @changes to the bridge.  The block,
		# if given, will be called with true and the response, or false
		# and an Exception.  This should only be called internally or
		# by the NLHue::Bridge.
		def send_changes(&block)
			msg = {}

			@changes.each do |param|
				case param
				when 'colormode'
					case @info[@api_target]['colormode']
					when 'hs'
						msg['hue'] = @info[@api_target]['hue'] if @changes.include? 'hue'
						msg['sat'] = @info[@api_target]['sat'] if @changes.include? 'sat'
					when 'xy'
						msg['xy'] = @info[@api_target]['xy']
					when 'ct'
						msg['ct'] = @info[@api_target]['ct']
					end

				when 'bri', 'on', 'alert', 'effect', 'scene'
					msg[param] = @info[@api_target][param]
				end
			end

			msg['transitiontime'] = @transitiontime if @transitiontime

			put_target(msg) do |status, result|
				rmsg = result.to_s
				# TODO: Parse individual parameters' error messages?  Example:
				# [{"error":{"type":6,"address":"/lights/2/state/zfhue","description":"parameter, zfhue, not available"}},{"success":{"/lights/2/state/transitiontime":0}}]
				@changes.delete('alert') if rmsg.include? 'Device is set to off'
				@changes.clear if status || rmsg =~ /(invalid value|not available)/
				yield status, result if block_given?
			end

			@transitiontime = nil
		end

		private
		# Sets one or more parameters on the local light, then sends
		# them to the bridge (unless defer was called).
		def set(params)
			params.each do |k, v|
				@changes << k
				@info[@api_target][k] = v
			end

			send_changes unless @defer
		end

		# PUTs the given Hash or Array, converted to JSON, to this
		# light or group's API endpoint.  The given block will be
		# called as described for NLHue::Bridge#put_api().
		def put_target(msg, &block)
			unless msg.is_a?(Hash) || msg.is_a?(Array)
				raise "Message to PUT must be a Hash or an Array, not #{msg.class.inspect}."
			end

			api_path = "/#{@api_category}/#{@id}/#{@api_target}"
			@bridge.put_api api_path, msg.to_json, @api_category do |response|
				status, result = @bridge.check_json response
				yield status, result if block_given?
			end
		end
	end
end
