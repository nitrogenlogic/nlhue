# A class representing a group of lights on a Hue bridge.
# (C)2013 Mike Bourgeous

require 'eventmachine'
require 'em/protocols/httpclient'
require 'rexml/document'
require 'json'
require 'set'

module NLHue
	# A class representing a designated group of lights on a Hue bridge.
	# Recommended use is to get a Group object by calling
	# NLHue::Bridge#groups().
	#
	# TODO: Much code is shared with Light; consolidate into a Target
	# superclass.
	class Group
		attr_reader :id, :name, :bridge

		# bridge - The Bridge that controls this light.
		# id - The group's ID (integer >= 0).
		# info - The Hash parsed from the JSON description of the
		# group, if available.  The group's membership will be unknown
		# until the JSON from the bridge (/api/[username]/groups/[id])
		# is passed here or to handle_json.
		def initialize bridge, id, info=nil
			@bridge = bridge
			@id = id
			@name = nil
			@lights = Set.new
			@changes = Set.new
			@defer = false
			@info = {'action' => {'xy' => [0.5, 0.5]}, 'lights' => []}
			handle_json info
		end

		# Updates this group's name and membership with the given Hash
		# parsed from the bridge's JSON.
		def handle_json info
			@info = info if info
			@name = info ? info['name'] :
				@name ? @name :
				"Lightset #{id}"
			info['lights'].each do |id|
				@lights << id.to_i
			end
			# FIXME: Handle removal of a light from a group
		end

		# Returns an array containing this group's corresponding Light
		# objects from the Bridge.
		def lights
			lights = @bridge.lights.values
			lights.select { |light| @lights.include? light.id }
		end

		# An array containing the IDs of the lights belonging to this
		# group.
		def light_ids
			@lights.to_a
		end

		# "Group: [ID]: [name] ([num] lights)"
		def to_s
			"Group: #{@id}: #{@name} (#{@lights.length} lights}"
		end

		# Returns a copy of the Hash passed to the constructor or to
		# handle_json.
		def to_h
			@info.clone
		end

		# Call to queue changes to be sent all at once.  Updates will
		# not be sent to the group until #submit is called.  Call
		# #nodefer to stop deferring changes.
		def defer
			@defer = true
		end

		# Stops deferring changes and sends any queued changes.
		def nodefer
			@defer = false
			set {}
		end

		# Sets the transition time in centiseconds used for the next
		# immediate parameter change or deferred batch parameter
		# change.  The transition time will be reset when send_changes
		# is called.  Call with nil to clear the transition time.
		def transitiontime= time
			time = 0 if time < 0
			@transitiontime = time.to_i
		end

		# Tells the Bridge object that this Group is ready to have its
		# deferred data sent.  Bridge will schedule a rate-limited call
		# to #send_changes, which sends all changes queued since the
		# last call to defer.  The block, if given, will be called with
		# true and the response on success, or false and an Exception
		# on error.  The transition time sent to the bridge can be
		# controlled with transitiontime=.  If no transition time is
		# set, the default transition time will be used by the bridge.
		def submit &block
			puts "Submitting changes to group #{self}" # XXX
			@bridge.add_target self, &block
		end

		# Returns a Hash containing the groups's most recently set
		# state (if any), as sent to the bridge's group 'action'.
		def state
			@info['action']
		end

		# Sets the group to flash once if repeat is false, or several
		# times if repeat is true.
		def alert! repeat=false
			set({ 'alert' => repeat ? 'select' : 'lselect' })
		end

		# Stops any existing flashing of the group.
		def clear_alert
			set({ 'alert' => 'none' })
		end

		# Sets the group's alert status to the given string (one of
		# 'select' (flash once), 'lselect' (flash several times), or
		# 'none' (stop flashing)).  Any other value may result in an
		# error from the bridge.
		def alert= alert
			set({ 'alert' => alert })
		end

		# Returns the alert state most recently set on the group (or
		# the stored state if defer() was called, but send() has not
		# yet been called).
		def alert
			@info['action']['alert']
		end

		# Sets the on/off state of this group (true or false).  Lights
		# must be turned on before other parameters can be changed.
		def on= on
			set({ 'on' => !!on })
		end

		# The group state most recently set with on=, on!() or off!().
		def on?
			@info['action']['on']
		end

		# Turns the group on.
		def on!
			self.on = true
		end

		# Turns the group off.
		def off!
			self.on = false
		end

		# Sets the brightness of this group (0-255 inclusive).  Note
		# that a brightness of 0 is not off.  The group's lights must
		# already be switched on for this to work.
		def bri= bri
			bri = 0 if bri < 0
			bri = 255 if bri > 255

			set({ 'bri' => bri.to_i })
		end

		# The brightness most recently set with bri=.
		def bri
			@info['action']['bri'].to_i
		end

		# Switches the group into color temperature mode and sets the
		# color temperature of the group in mireds (154-500 inclusive,
		# where 154 is highest temperature (bluer), 500 is lowest
		# temperature (yellower)).  The group's lights must be on for
		# this to work.
		def ct= ct
			ct = 154 if ct < 154
			ct = 500 if ct > 500

			set({ 'ct' => ct.to_i, 'colormode' => 'ct' })
		end

		# The color temperature most recently set with ct=.
		def ct
			@info['action']['ct'].to_i
		end

		# Switches the group into CIE XYZ color mode and sets the X
		# color coordinate to the given floating point value between 0
		# and 1, inclusive.  Note that the Y coordinate assigned to the
		# group will be undefined unless y= or xy= is also called.  The
		# group's lights must be on for this to work.
		def x= x
			self.xy = [ x, @info['action']['xy'][1] ]
		end

		# The X color coordinate most recently set with x= or xy=.
		def x
			@info['action']['xy'][0].to_f
		end

		# Switches the group into CIE XYZ color mode and sets the Y
		# color coordinate to the given floating point value between 0
		# and 1, inclusive.  Note that the X coordinate assigned to the
		# group will be undefined unless x= or xy= is also called.  The
		# group's lights must be on for this to work.
		def y= y
			self.xy = [ @info['action']['xy'][0], y ]
		end

		# The Y color coordinate most recently set with y= or xy=.
		def y
			@info['action']['xy'][1].to_f
		end

		# Switches the group into CIE XYZ color mode and sets the XY
		# color coordinates to the given two-element array of floating
		# point values between 0 and 1, inclusive.  The group's lights
		# must be on for this to work.
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

		# The XY color coordinates most recently set with xy=.
		def xy
			xy = @info['action']['xy']
			[ xy[0].to_f, xy[1].to_f ]
		end

		# Switches the group into hue/saturation mode and sets the
		# group's hue to the given value (floating point degrees,
		# wrapped to 0-360).  The group's lights must be on for this to
		# work.
		def hue= hue
			hue = (hue * 65536 / 360).to_i & 65535

			set({ 'hue' => hue, 'colormode' => 'hs' })
		end

		# The hue most recently set with hue=.
		def hue
			@info['action']['hue'].to_i * 360 / 65536.0
		end

		# Switches the group into hue/saturation mode and sets the
		# group's saturation to the given value (0-255 inclusive).
		def sat= sat
			sat = 0 if sat < 0
			sat = 255 if sat > 255

			set({ 'sat' => sat.to_i, 'colormode' => 'hs' })
		end

		# The saturation most recently set with saturation=.
		def sat
			@info['action']['sat'].to_i
		end

		# Sets the group's effect mode (either 'none' or 'colorloop').
		def effect= effect
			effect = 'none' unless effect == 'colorloop'
			set({ 'effect' => effect})
		end

		# The effect mode most recently set with effect=.
		def effect
			@info['state']['effect']
		end

		# Returns the group's last set color mode ('ct' for color
		# temperature, 'hs' for hue/saturation, 'xy' for CIE XYZ).
		def colormode
			@info['action']['colormode']
		end

		# Sends parameters named in @changes to the bridge.  The block,
		# if given, will be called with true and the response, or false
		# and an Exception.
		def send_changes &block
			msg = {}

			@changes.each do |param|
				case param
				when 'colormode'
					case @info['action']['colormode']
					when 'hs'
						msg['hue'] = @info['action']['hue'] if @changes.include? 'hue'
						msg['sat'] = @info['action']['sat'] if @changes.include? 'sat'
					when 'xy'
						msg['xy'] = @info['action']['xy']
					when 'ct'
						msg['ct'] = @info['action']['ct']
					end

				when 'bri', 'on', 'alert', 'effect'
					msg[param] = @info['action'][param]
				end
			end
			@changes.clear

			msg['transitiontime'] = @transitiontime if @transitiontime

			put_group msg, &block

			@transitiontime = nil
		end

		private
		# Sets one or more parameters in the stored info Hash, then
		# sends them to the bridge (unless defer was called).
		def set params
			params.each do |k, v|
				@changes << k
				@info['action'][k] = v
			end

			send_changes unless @defer
		end

		# PUTs the given Hash or Array, converted to JSON, to this
		# group's API endpoint.  The given block will be called as
		# described for NLHue::Bridge#put_api().
		def put_group msg, &block
			unless msg.is_a?(Hash) || msg.is_a?(Array)
				raise "Message to PUT must be a Hash or an Array, not #{msg.class.inspect}."
			end

			@bridge.put_api "/groups/#{@id}/action", msg.to_json do |response|
				status, result = @bridge.check_json response
				yield status, result if block_given?
			end
		end
	end
end
