#!/usr/bin/env ruby1.9.1
# Attempts to get information from each bridge and light.
# (C)2012 Mike Bourgeous

require_relative '../lib/nlhue'

USER = ENV['HUE_USER'] || 'testing1234'

EM.run do
	NLHue.discover(3) do |response|
		response.username = USER
		response.update do |status, result|
			puts "Update: #{response}: #{status}, #{result}"
			puts result.backtrace if result.is_a? Exception

			response.lights.each do |light|
				puts "A light: #{light}"
				light.update do |status, result|
					puts "Light #{light} update: #{status}, #{result}"
					puts result.backtrace if result.is_a? Exception

					light.on!
					light.hue = rand 360
				end
			end
		end
	end
	EM.add_timer(4) do
		EM.stop_event_loop
	end
end
