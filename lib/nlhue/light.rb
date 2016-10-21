# A class representing a light known to a Hue bridge.
# (C)2013-2015 Mike Bourgeous

module NLHue
	# A class representing a light known to a Hue bridge.  Recommended use
	# is to get a Light object by calling NLHue::Bridge#lights().
	class Light < Target
		# bridge - The Bridge that controls this light.
		# id - The bulb number.
		# info - Parsed Hash of the JSON light info object from the bridge.
		def initialize(bridge, id, info=nil)
			super bridge, id, info, :lights, 'state'
		end

		# "Light: [ID]: [name] ([type])"
		def to_s
			"Light: #{@id}: #{@name} (#{@type})"
		end
	end
end
