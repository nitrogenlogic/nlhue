#!/usr/bin/env ruby
# Runs periodic Bridge discovery for a while with a short discovery interval.
# (C)2013 Mike Bourgeous

require_relative '../lib/nlhue'

USER = ENV['HUE_USER'] || 'testing1234'

EM.run do
	disco_cb = NLHue::Disco.add_disco_callback do |event, param, msg|
		puts if event == :start
		puts "Disco event: #{event}, #{param}, #{msg}"
		if event == :start
			puts "Starting with #{NLHue::Disco.bridges.size} bridge(s)"
		elsif event == :end
			puts "Ended, #{param ? 'now' : 'still'} #{NLHue::Disco.bridges.size} bridge(s)"
		end
	end
	bridge_cb = NLHue::Bridge.add_bridge_callback do |bridge, status|
		puts "Bridge event: #{bridge.serial} is now #{status ? 'available' : 'unavailable'}"
		bridge.update if status && !bridge.registered?
	end

	puts "--- Starting discovery"
	NLHue::Disco.start_discovery(USER, 1)

	EM.add_timer(10) do
		puts "\n\n--- Stopping discovery"
		NLHue::Disco.stop_discovery
		NLHue::Disco.remove_disco_callback disco_cb
	end
	EM.add_timer(12) do
		puts "\n\n--- Starting discovery"
		NLHue::Disco.add_disco_callback disco_cb
		NLHue::Disco.start_discovery(USER, 1)
	end

	EM.add_timer(19) do
		puts "\n\n--- Forcing discovery"
		NLHue::Disco.do_disco
	end
	EM.add_timer(20) do
		puts "\n\n--- Stopping discovery shortly after starting"
		NLHue::Disco.stop_discovery
		NLHue::Disco.remove_disco_callback disco_cb
	end
	EM.add_timer(21) do
		puts "\n\n--- Starting discovery with invalid username"
		NLHue::Disco.add_disco_callback disco_cb
		NLHue::Disco.start_discovery('invaliduser', 1)
	end

	EM.add_timer(30) do
		puts "\n\n--- Exiting"
		NLHue::Disco.stop_discovery
		EM.add_timer(1) do
			EM.stop_event_loop
		end
	end
end
