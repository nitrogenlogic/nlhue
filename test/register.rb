#!/usr/bin/env ruby1.9.1
# Attempts to register a username with all detected Hue bridges.
# (C)2012 Mike Bourgeous

require_relative '../lib/nlhue'

EM.run do
	NLHue.discover(3) do |response|
		response.register 'testing123', 'Test Device' do |status, result|
			puts "Register result: #{status}, #{result}"
		end
	end
	EM.add_timer(3) do
		EM.stop_event_loop
	end
end
