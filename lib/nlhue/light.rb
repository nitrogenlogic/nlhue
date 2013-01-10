# A class representing a light known to a Hue bridge.
# (C)2012 Mike Bourgeous

require 'eventmachine'
require 'em/protocols/httpclient'
require 'rexml/document'
require 'json'
require 'set'

module NLHue
	# A class representing a light known to a Hue bridge.  Recommended use
	# is to get a Light object by calling NLHue::Bridge#lights().
	class Light
		attr_reader :id, :type, :name

		# bridge - The Bridge that controls this light.
		# id - The bulb number.
		# info - Parsed Hash of the JSON light info object from the bridge.
		def initialize bridge, id, info
			@bridge = bridge
			@id = id
			@changes = Set.new
			@defer = false
			handle_json info
		end

		# Updates this Light object using a Hash parsed from the JSON
		# light info from the bridge (either /api/XXX or
		# /api/XXX/lights/ID).
		def handle_json info
			raise "Light info must be a Hash, not #{info.class}." unless info.is_a?(Hash)
			@info = info
			@type = info['type']
			@name = info['name']
			@info['id'] = @id
		end

		# Gets the current state of this light from the bridge.  The
		# block, if given, will be called with true and the response on
		# success, or false and an Exception on error.
		def update &block
			@bridge.get_api "/lights/#{@id}" do |response|
				puts "Light update response: #{response}" # XXX

				status, result = @bridge.check_json(response)

				begin
					handle_json result
				rescue => e
					status = false
					result = e
				end

				yield status, result if block_given?
			end
		end

		# "Light: [ID]: [name] ([type])"
		def to_s
			"Light: #{@id}: #{@name} (#{@type})"
		end

		# Returns a copy of the hash representing the light's state as
		# parsed from the JSON returned by the bridge.
		def to_h
			@info.clone
		end

		# Call to queue changes to be sent all at once.  Updates will
		# no longer be sent to the light until send is called, after
		# which changes will no longer be deferred.
		def defer
			@defer = true
		end

		# Sets the transition time in centiseconds used for the next
		# call to send.  The transition time will be reset when send is
		# called.  The transition time will not be set if defer has not
		# been called.  Call with nil to clear the transition time.
		def transitiontime= time
			if @defer
				time = 0 if time < 0
				@transitiontime = time.to_i
			end
		end

		# Sends all changes queued since the last call to defer.  The
		# block, if given, will be called with true and the response on
		# success, or false and an Exception on error.  The transition
		# time sent to the bridge can be controlled with
		# transitiontime=.  If no transition time is set, the default
		# transition time will be used by the bridge.
		def send &block
			send_changes &block
			@defer = false
			@transitiontime = nil
		end

		# Sets the light to flash once if repeat is false, or several
		# times if repeat is true.
		def alert! repeat=false
			set({ 'alert' => repeat ? 'select' : 'lselect' })
		end

		# Stops any existing flashing of the light.
		def clear_alert
			set({ 'alert' => 'none' })
		end

		# Sets the light's alert status to the given string (one of
		# 'select' (flash once), 'lselect' (flash several times), or
		# 'none' (stop flashing)).  Any other value may result in an
		# error from the bridge.
		def alert= alert
			set({ 'alert' => alert })
		end

		# Returns the current alert state of the light (or the stored
		# state if defer() was called, but send() has not yet been
		# called).
		def alert
			@info['state']['alert']
		end

		# Sets the on/off state of this light (true or false).  The
		# light must be turned on before other parameters can be
		# changed.
		def on= on
			set({ 'on' => !!on })
		end

		# The light state most recently set with on=, on!() or off!(),
		# or the last light state received from the light due to
		# calling update() on the light or on the bridge.
		def on?
			@info['state']['on']
		end

		# Turns the light on.
		def on!
			self.on = true
		end

		# Turns the light off.
		def off!
			self.on = false
		end

		# Sets the brightness of this light (0-255 inclusive).  Note
		# that a brightness of 0 is not off.  The light must already be
		# switched on for this to work.
		def bri= bri
			bri = 0 if bri < 0
			bri = 255 if bri > 255

			set({ 'bri' => bri.to_i })
		end

		# The brightness most recently set with bri=, or the last
		# brightness received from the light due to calling update() on
		# the light or on the bridge.
		def bri
			@info['state']['bri'].to_i
		end

		# Switches the light into color temperature mode and sets the
		# color temperature of the light in mireds (154-500 inclusive,
		# where 154 is highest temperature (bluer), 500 is lowest
		# temperature (yellower)).  The light must be on for this to
		# work.
		def ct= ct
			ct = 154 if ct < 154
			ct = 500 if ct > 500

			set({ 'ct' => ct.to_i, 'colormode' => 'ct' })
		end

		# The color temperature most recently set with ct=, or the last
		# color temperature received from the light due to calling
		# update() on the light or on the bridge.
		def ct
			@info['state']['ct'].to_i
		end

		# Switches the light into CIE XYZ color mode and sets the X
		# color coordinate to the given floating point value between 0
		# and 1, inclusive.  The light must be on for this to work.
		def x= x
			self.xy = [ x, @info['state']['xy'][1] ]
		end

		# The X color coordinate most recently set with x= or xy=, or
		# the last X color coordinate received from the light.
		def x
			@info['state']['xy'][0].to_f
		end

		# Switches the light into CIE XYZ color mode and sets the Y
		# color coordinate to the given floating point value between 0
		# and 1, inclusive.  The light must be on for this to work.
		def y= y
			self.xy = [ @info['state']['xy'][0], y ]
		end

		# The Y color coordinate most recently set with y= or xy=, or
		# the last Y color coordinate received from the light.
		def y
			@info['state']['xy'][1].to_f
		end

		# Switches the light into CIE XYZ color mode and sets the XY
		# color coordinates to the given two-element array of floating
		# point values between 0 and 1, inclusive.  The light must be
		# on for this to work.
		def xy= xy
			unless xy.is_a?(Array) && xy.length == 2 && xy[0].is_a?(Numeric) && xy[1].is_a?(Numeric)
				raise 'Pass a two-element array of numbers to xy=.'
			end

			xy[0] = 0 if xy[0] < 0
			xy[0] = 1 if xy[0] > 1
			xy[1] = 0 if xy[1] < 0
			xy[1] = 1 if xy[1] > 1

			set({ 'xy' => xy, 'colormode' => 'xy' })
		end

		# The XY color coordinates most recently set with x=, y=, or
		# xy=, or the last color coordinates received from the light
		# due to calling update() on the light or on the bridge.
		def xy
			xy = @info['state']['xy']
			[ xy[0].to_f, xy[1].to_f ]
		end

		# Switches the light into hue/saturation mode and sets the
		# light's hue to the given value (floating point degrees,
		# wrapped to 0-360).  The light must already be switched on for
		# this to work.
		def hue= hue
			puts "Hue #{hue}"# XXX
			hue = (hue * 65536 / 360).to_i & 65535
			puts "Hue2 #{hue}" # XXX

			set({ 'hue' => hue, 'colormode' => 'hs' })
		end

		# The hue most recently set with hue=, or the last hue received
		# from the light due to calling update() on the light or on the
		# bridge.
		def hue
			@info['state']['hue'].to_i * 360 / 65536.0
		end

		# Switches the light into hue/saturation mode and sets the
		# light's saturation to the given value (0-255 inclusive).
		def sat= sat
			sat = 0 if sat < 0
			sat = 255 if sat > 255

			set({ 'sat' => sat.to_i, 'colormode' => 'hs' })
		end

		# The saturation most recently set with saturation=, or the
		# last saturation received from the light due to calling
		# update() on the light or on the bridge.
		def sat
			@info['state']['sat'].to_i
		end

		# Returns the light's current color mode ('ct' for color
		# temperature, 'hs' for hue/saturation, 'xy' for CIE XYZ).
		def colormode
			@info['state']['colormode']
		end

		private
		# Sets one or more parameters on the local light, then sends
		# them to the bridge (unless defer was called).
		def set params
			params.each do |k, v|
				@changes << k
				@info['state'][k] = v
			end

			send_changes unless @defer
		end

		# Sends parameters named in @changes to the bridge.  The block,
		# if given, will be called with true and the response, or false
		# and an Exception.
		def send_changes &block
			msg = {}

			@changes.each do |param|
				case param
				when 'colormode'
					case @info['state']['colormode']
					when 'hs'
						msg['hue'] = @info['state']['hue'] if @changes.include? 'hue'
						msg['sat'] = @info['state']['sat'] if @changes.include? 'sat'
					when 'xy'
						msg['xy'] = @info['state']['xy']
					when 'ct'
						msg['ct'] = @info['state']['ct']
					end

				when 'bri', 'on', 'alert'
					msg[param] = @info['state'][param]
				end
			end
			@changes.clear

			msg['transitiontime'] = @transitiontime if @transitiontime

			put_light msg, &block
		end

		# PUTs the given Hash or Array, converted to JSON, to this
		# light's API endpoint.  The given block will be called as
		# described for NLHue::Bridge#put_api().
		def put_light msg, &block
			unless msg.is_a?(Hash) || msg.is_a?(Array)
				raise "Message to PUT must be a Hash or an Array, not #{msg.class.inspect}."
			end

			@bridge.put_api "/lights/#{@id}/state", msg.to_json do |response|
				status, result = @bridge.check_json response
				yield status, result if block_given?
			end
		end
	end
end
