# A class representing a light known to a Hue bridge.
# (C)2012 Mike Bourgeous

require 'eventmachine'
require 'em/protocols/httpclient'
require 'rexml/document'
require 'json'

module NLHue
	# A class representing a light known to a Hue bridge.
	# A class representing a Hue bridge.  A Bridge object might not refer
	# to an actual Hue bridge if verify() hasn't succeeded.
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

		# Sets the brightness of this light (0-254 inclusive).  Note
		# that a brightness of 0 is not off.  The light must already be
		# switched on for this to work.
		def bri= bri
			raise 'Brightness must be between 0 and 254, inclusive.' unless bri >= 0 && bri <= 254

			@info['state']['bri'] = bri

			msg = { 'bri' => @info['state']['bri'] }

			put_light msg do |response|
				puts "Brightness result: #{response}" # XXX
			end
		end

		# The brightness most recently set with bri=, or the last
		# brightness received from the light due to calling update() on
		# the light or on the bridge.
		def bri
			@info['state']['bri']
		end

		# Switches the light into hue/saturation mode, and sets the
		# light's hue to the given value (floating point degrees,
		# wrapped to 0-360).  The light must already be switched on for
		# this to work.
		def hue= hue
			puts "Hue #{hue}"# XXX
			hue = (hue * 65536 / 360).to_i & 65535
			puts "Hue2 #{hue}" # XXX

			@info['state']['hue'] = hue
			@info['state']['colormode'] = 'hue'

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
			@info['state']['hue']
		end

		# Switches the light into hue/saturation mode, and sets the
		# light's saturation to the given value (0-254 inclusive).
		def sat= sat
			raise 'Saturation must be between 0 and 254, inclusive.' unless sat >= 0 && sat <= 254

			@info['state']['sat'] = sat.to_i
			@info['state']['colormode'] = 'hue'

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
			@info['state']['sat']
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
