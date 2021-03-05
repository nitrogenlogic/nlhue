#!/usr/bin/env ruby
# Attempts to get information from each bridge and light, then sets each light
# to a random color.
# (C)2013 Mike Bourgeous

require_relative '../lib/nlhue'

USER = ENV['HUE_USER'] || 'testing1234'

EM.run do
	NLHue::Bridge.add_bridge_callback do |bridge, status|
		puts "Bridge event: #{bridge.serial} is now #{status ? 'available' : 'unavailable'}"
	end
	NLHue::Disco.send_discovery(3) do |response|
		response.username = USER
		response.update do |status, result|
			puts "Update: #{response}: #{status}, #{result}"
			puts result.backtrace if result.is_a? Exception

			response.lights.each_value do |light|
				puts "A light: #{light}"

				# FIXME: Updates frequently fail:
				# Light: 5: Hue Downlight 1 (Extended color light) update: false, No response received.
				# /home/nitrogen/devel/hue/nlhue/lib/nlhue/bridge.rb:573:in `check_json'
				# /home/nitrogen/devel/hue/nlhue/lib/nlhue/target.rb:68:in `block in update'
				# /home/nitrogen/devel/hue/nlhue/lib/nlhue/request_queue.rb:112:in `block in do_request'
				light.update do |status, result|
					puts "#{light} update: #{status}, #{result}"
					puts result.backtrace if result.is_a? Exception

					light.on!
					light.defer
					light.bri = 255
					light.hue = rand 360
					light.sat = rand(75) + 180
					light.submit
				end

				sleep 0.5
			end
		end
	end
	EM.add_timer(8) do
		EM.stop_event_loop
	end
end
