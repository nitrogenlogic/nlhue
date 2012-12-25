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

		def to_s
			"Light: #{@id}: #{@name} (#{@type})"
		end

		def hue= hue
			puts "Hue #{hue}"# XXX
			hue = (hue * 65536 / 360).to_i % 65536
			puts "Hue2 #{hue}" # XXX

			@info['state']['hue'] = hue

			@bridge.put_api "/lights/#{@id}/state", {'hue' => hue}.to_json do |status, result|
				puts "Hue result: #{status}, #{result}" # XXX
			end
		end

		def hue
			@info['state']['hue']
		end
	end
end
