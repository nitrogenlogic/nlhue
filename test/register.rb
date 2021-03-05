#!/usr/bin/env ruby
# Attempts to register and unregister a username with all detected Hue bridges.
# (C)2013 Mike Bourgeous

require_relative '../lib/nlhue'

EM.run do
	NLHue::Bridge.add_bridge_callback do |bridge, status|
		puts "Bridge event: #{bridge.serial} is now #{status ? 'available' : 'unavailable'}"
	end
	NLHue::Disco.send_discovery(3) do |response|
		puts "Registering with #{response}"
		response.register 'Test Device (nlhue)' do |status, result|
			puts "Register result: #{status}, #{result}"

			puts "\nUpdating #{response}"
			response.update do |status, result|
				puts "Update result: #{status}, #{result}"
				
				puts "\nUnregistering."
				response.unregister do |status, result|
					puts "Unregister result: #{status}, #{result}"
					EM.next_tick do
						EM.stop_event_loop
                                        end
				end
			end
		end
	end
	EM.add_timer(5) do
		puts "Timed out after 5 seconds"
		EM.stop_event_loop
	end
end
