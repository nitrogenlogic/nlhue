#!/usr/bin/env ruby1.9.1
# Attempts to get information from each bridge and light.
# (C)2013 Mike Bourgeous

require_relative '../lib/nlhue'

USER = ENV['HUE_USER'] || 'testing1234'

EM.run do
	NLHue.discover(3) do |response|
		response.username = USER
		response.update do |status, result|
			puts "Update: #{response}: #{status}, #{result}"
			puts result.backtrace if result.is_a? Exception

			response.lights.each_value do |light|
				puts "A light: #{light}"
				light.update do |status, result|
					puts "Light #{light} update: #{status}, #{result}"
					puts result.backtrace if result.is_a? Exception

					light.on!
					light.defer
					light.bri = 255
					light.hue = rand 360
					light.sat = rand(75) + 180
					light.send
				end
			end
		end
	end
	EM.add_timer(4) do
		EM.stop_event_loop
	end
end
