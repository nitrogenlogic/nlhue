#!/usr/bin/env ruby
# Prints all responses received from a search for Hue hubs.
# (C)2013 Mike Bourgeous

require_relative '../lib/nlhue'

EM.run do
	NLHue::Bridge.add_bridge_callback do |bridge, status|
		puts "Bridge event: #{bridge.serial} is now #{status ? 'available' : 'unavailable'}"
	end
	NLHue::Disco.send_discovery(3) do |response|
		puts response
	end
	EM.add_timer(3) do
		EM.stop_event_loop
	end
end
