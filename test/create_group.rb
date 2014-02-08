#!/usr/bin/env ruby1.9.1
# Attempts to create, modify, and delete a group on a discovered bridge.
# (C)2014 Mike Bourgeous

require_relative '../lib/nlhue'

USER = ENV['HUE_USER'] || 'testing1234'

EM.run do
	NLHue::Bridge.add_bridge_callback do |bridge, status|
		puts "Bridge event: #{bridge.serial} is now #{status ? 'available' : 'unavailable'}"
	end

	NLHue::Disco.send_discovery(3) do |bridge|
		bridge.username = USER
		bridge.update do |status, result|
			puts "Update: #{bridge}: #{status}, #{result}"
			puts result.backtrace if result.is_a? Exception

			puts "Creating group..."
			bridge.create_group "Test Group", bridge.lights.values.select{|l| l.id.odd? } do |status, group|
				puts "Group creation result: #{status} group: #{group}"
				puts group.backtrace if group.is_a? Exception

				# New groups can take a few seconds before
				# their status and lights show up on the bridge
				puts "Waiting for bridge to initialize group..."
				EM.add_timer(3) do
					puts "Turning on group..."
					group.defer
					group.on!
					group.effect = 'colorloop'
					group.submit do |status, result|
						puts "Group modification result: #{status}, #{result}"

						puts "Deleting group..."
						bridge.delete_group group do |status, result|
							puts "Group deletion result: #{status}, #{result}"

							puts "Exiting..."
							EM.stop_event_loop
						end
					end
				end
			end
		end
	end

	EM.add_timer(8) do
		puts "Exiting due to timeout..."
		EM.stop_event_loop
	end
end

