# A class representing a light known to a Hue bridge.
# (C)2012 Mike Bourgeous

require 'eventmachine'
require 'em/protocols/httpclient'
require 'rexml/document'
require 'json'

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
			handle_json info
		end

		# Updates this Light object using a Hash parsed from the JSON
		# light info from the bridge (either /api/XXX or
		# /api/XXX/lights/ID).
		def handle_json info
			@info = info
			@type = info['type']
			@name = info['name']
			# TODO: Hue/sat/bri/ct/etc.
		end

		# Gets the current state of this light from the bridge.
		def update &block
			@bridge.get_api "/lights/#{@id}" do |response|
				# TODO: Move this pattern into a helper function
				puts "Light update response: #{response}" # XXX

				status = true
				result = response

				begin
					handle_json @bridge.check_json(response)
				rescue => e
					status = false
					result = e
				end

				yield status, result
			end
		end

		# "Light: [ID]: [name] ([type])"
		def to_s
			"Light: #{@id}: #{@name} (#{@type})"
		end

		# Sets the on/off state of this light (true or false).  The
		# light must be turned on before other parameters can be
		# changed.
		def on= on
			@info['state']['on'] = !!on

			msg = { 'on' => @info['state']['on'] }

			put_light msg do |response|
				puts "On/off result: #{response}"
			end
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

			@info['state']['bri'] = bri.to_i

			msg = { 'bri' => @info['state']['bri'] }

			put_light msg do |response|
				puts "Brightness result: #{response}" # XXX
			end
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

			@info['state']['ct'] = ct.to_i
			@info['state']['colormode'] = 'ct'

			msg = { 'ct' => @info['state']['ct'] }

			put_light msg do |response|
				# TODO: Update internal state using success response?
				puts "Color temperature result: #{response}" # XXX
			end
		end

		# The color temperature most recently set with ct=, or the last
		# color temperature received from the light due to calling
		# update() on the light or on the bridge.
		def ct
			@info['state']['ct'].to_i
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

			@info['state']['xy'] = xy
			@info['state']['colormode'] = 'xy'

			msg = { 'ct' => @info['state']['xy'] }

			put_light msg do |response|
				puts "XY result: #{response}"
			end
		end

		# The XY color coordinates most recently set with xy=, or the
		# last color coordinates received from the light due to calling
		# update() on the light or on the bridge.
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

			@info['state']['hue'] = hue
			@info['state']['colormode'] = 'hs'

			msg = {
				'hue' => @info['state']['hue'],
				'sat' => @info['state']['sat'],
			}

			put_light msg do |response|
				puts "Hue result: #{response}" # XXX
			end
		end

		# The hue most recently set with hue=, or the last hue received
		# from the light due to calling update() on the light or on the
		# bridge.
		def hue
			@info['state']['hue'].to_i
		end

		# Switches the light into hue/saturation mode and sets the
		# light's saturation to the given value (0-255 inclusive).
		def sat= sat
			sat = 0 if sat < 0
			sat = 255 if sat > 255

			@info['state']['sat'] = sat.to_i
			@info['state']['colormode'] = 'hs'

			msg = {
				'hue' => @info['state']['hue'],
				'sat' => @info['state']['sat'],
			}

			put_light msg do |response|
				puts "Sat result: #{response}" # XXX
			end
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

		# PUTs the given Hash or Array, converted to JSON, to this
		# light's API endpoint.  The given block will be called as
		# described for NLHue::Bridge#put_api().
		def put_light msg, &block
			unless msg.is_a?(Hash) || msg.is_a?(Array)
				raise "Message to PUT must be a Hash or an Array, not #{msg.class.inspect}."
			end

			@bridge.put_api "/lights/#{@id}/state", msg.to_json, &block
		end
	end
end
