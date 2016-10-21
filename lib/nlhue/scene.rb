# A class representing a preset scene on a Hue bridge.
# (C)2015 Mike Bourgeous

module NLHue
	# Represents a preset scene on a Hue bridge, with a list of included
	# lights.  The actual values recalled by the scene are not available.
	# TODO: Support creating new scenes
	class Scene
		attr_reader :id, :name, :bridge

		# bridge - The Bridge that contains this scene.
		# id - The scene's ID (a String).
		# info - A Hash with scene info from the bridge.
		def initialize(bridge, id, info)
			@bridge = bridge
			@id = id
			@info = info
			@lights = Set.new

			handle_json(info)
		end

		# Updates this scene with any changes from the bridge.
		def handle_json(info)
			raise "Scene info must be a Hash" unless info.is_a?(Hash)

			info['id'] = @id

			@name = info['name'] || @name

			if info['lights'].is_a?(Array) && !info['lights'].empty?
				@lights.replace info['lights'].map(&:to_i)
			end

			@info = info
		end

		# Returns a copy of the last received info from the bridge, plus
		# the scene's ID.
		def to_h
			@info.clone
		end

		# Returns a description of this scene.
		def to_s
			"Scene #{@id}: #{@name} (#{@lights.count} lights)"
		end

		# Returns a Hash containing basic information about the scene.
		def state
			{
				id: @id,
				name: @name,
				lights: light_ids,
			}
		end

		# Converts the Hash returned by #state to JSON.
		def to_json(*args)
			state.to_json(*args)
		end

		# Returns an array containing this scene's corresponding Light
		# objects from the Bridge.
		def lights
			lights = @bridge.lights
			@lights.map{|id| lights[id]}
		end

		# An array containing the IDs of the lights belonging to this
		# scene.
		def light_ids
			@lights.to_a
		end

		# Recalls this scene on the next RequestQueue tick using group 0
		# (all lights).  The block, if given, will be called after the
		# scene is recalled.
		def recall(&block)
			@bridge.add_target self, &block
		end

		# Recalls this scene immediately using NLHue::Bridge#put_api.
		def send_changes(&block)
			@bridge.put_api '/groups/0/action', {scene: @id}.to_json, :groups, &block
		end
	end
end
