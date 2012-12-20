#!/usr/bin/env ruby1.9.1
# Prints all responses received from a search for Hue hubs.
# (C)2012 Mike Bourgeous

require_relative '../lib/nlhue'

EM.run do
	NLHue.discover(3) do |response|
		puts response
	end
	EM.add_timer(3) do
		EM.stop_event_loop
	end
end