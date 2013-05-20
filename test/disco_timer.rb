#!/usr/bin/env ruby1.9.1
# Runs periodic Bridge discovery for a while with a short discovery interval.
# (C)2013 Mike Bourgeous

require_relative '../lib/nlhue'

EM.run do
	disco_cb = NLHue::Disco.add_disco_callback do |event, param|
		puts "Disco event: #{event}, #{param}"
	end
	bridge_cb = NLHue::Bridge.add_bridge_callback do |bridge, status|
		puts "Bridge event: #{bridge.serial} is now #{status ? 'available' : 'unavailable'}"
	end

	NLHue::Disco.start_discovery('testing1234', 1)

	EM.add_timer(10) do
		puts "Stopping discovery"
		NLHue::Disco.stop_discovery
		NLHue::Disco.remove_disco_callback disco_cb
	end
	EM.add_timer(12) do
		puts "Starting discovery"
		NLHue::Disco.add_disco_callback disco_cb
		NLHue::Disco.start_discovery('testing1234', 1)
	end

	EM.add_timer(20) do
		puts "Stopping discovery"
		NLHue::Disco.stop_discovery
		NLHue::Disco.remove_disco_callback disco_cb
	end
	EM.add_timer(21) do
		puts "Starting discovery with invalid username"
		NLHue::Disco.add_disco_callback disco_cb
		NLHue::Disco.start_discovery('invaliduser', 1)
	end

	EM.add_timer(30) do
		puts "Exiting"
		NLHue::Disco.stop_discovery
		EM.add_timer(1) do
			EM.stop_event_loop
		end
	end
end
