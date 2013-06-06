#!/usr/bin/env ruby1.9.1
# Tests scanning for new lights.
# (C)2013 Mike Bourgeous

require_relative '../lib/nlhue'

USER = ENV['HUE_USER'] || 'testing1234'

EM.run do
	NLHue::Bridge.add_bridge_callback do |bridge, status|
		puts "Bridge event: #{bridge.serial} is now #{status ? 'available' : 'unavailable'}"
	end

	scan_timer = EM::Timer.new(6) do
		puts "No bridges found.  Exiting."
		EM.stop_event_loop
	end

	NLHue::Disco.send_discovery(3) do |br|
		br.username = USER

		br.add_update_callback do |status, result|
			if !status
				puts "Bridge #{br.serial} failed to update: #{result}"
			end

			if br.scan_active?
				puts "Scan ongoing: #{br.scan_status.inspect}"
			else
				puts "Scan complete.  Exiting."
				EM.stop_event_loop
			end
		end

		puts "Starting light scan on #{br.serial}"
		br.scan_lights

		br.subscribe

		scan_timer.cancel
	end
end
