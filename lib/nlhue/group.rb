# A class representing a group of lights on a Hue bridge.
# (C)2013-2015 Mike Bourgeous

module NLHue
	# A class representing a designated group of lights on a Hue bridge.
	# Recommended use is to call NLHue::Bridge#groups.
	class Group < Target
		# bridge - The Bridge that controls this light.
		# id - The group's ID (integer >= 0).
		# info - The Hash parsed from the JSON description of the group,
		# if available.  The group's lights will be unknown until the
		# JSON from the bridge (/api/[username]/groups/[id]) is passed
		# here or to #handle_json.
		def initialize(bridge, id, info=nil)
			@lights ||= Set.new

			super bridge, id, info, :groups, 'action'
		end

		# Updates this Group with data parsed from the Hue bridge.
		def handle_json(info)
			super info

			# A group returns no lights for a short time after creation
			if @info['lights'].is_a?(Array) && !@info['lights'].empty?
				@lights.replace @info['lights'].map(&:to_i)
			end
		end

		# "Group: [ID]: [name] ([num] lights)"
		def to_s
			"Group: #{@id}: #{@name} (#{@lights.length} lights}"
		end

		# Returns an array containing this group's corresponding Light
		# objects from the Bridge.
		def lights
			lights = @bridge.lights
			@lights.map{|id| lights[id]}
		end

		# An array containing the IDs of the lights belonging to this
		# group.
		def light_ids
			@lights.to_a
		end

		# Returns a Hash containing the group's info and most recently
		# set state, with symbolized key names and hue scaled to 0..360.
		# Example:
		# {
		#    :id => 0,
		#    :name => 'Lightset 0',
		#    :type => 'LightGroup',
		#    :lights => [0, 1, 2],
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
			{lights: light_ids}.merge!(super)
		end

		# Recalls +scene+, which may be a Scene object or a scene ID
		# String, on this group only.  Any raw ID String will not be
		# verified.  If NLHue::Target#defer was called, the scene will
		# not be recalled until #submit is called.
		def recall_scene(scene)
			scene = scene.id if scene.is_a?(Scene)
			raise 'Scene ID to recall must be a String' unless scene.is_a?(String)
			set('scene' => scene)
		end
	end
end
