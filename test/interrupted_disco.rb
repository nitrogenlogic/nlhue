#!/usr/bin/env ruby1.9.1
# Repeatedly starts then interrupts discovery to make sure that bridges aren't
# added after discovery is stopped.
# (C)2013 Mike Bourgeous

require_relative '../lib/nlhue'

USER = ENV['HUE_USER'] || 'testing1234'

running = false
avail = 0

EM.run do

	disco_cb = NLHue::Disco.add_disco_callback do |event, param, msg|
		puts "Disco event: #{event}, #{param}, #{msg}"
		case event
		when :start
			puts "Starting with #{NLHue::Disco.bridges.size} bridge(s)"
			raise "\e[1mXXXXXX Started more than once XXXXXX\e[0m" if running
			running = true
		when :end
			puts "Ended, #{param ? 'now' : 'still'} #{NLHue::Disco.bridges.size} bridge(s)"
			raise "\e[1mXXXXXX Ended more than once XXXXXX\e[0m" unless running
			running = false
		end
	end

	bridge_cb = NLHue::Bridge.add_bridge_callback do |bridge, status|
		avail += status ? 1 : -1
		puts "Bridge event: #{bridge.serial} is now #{status ? 'available' : 'unavailable'}"
		puts 'Bridge event came while discovery was stopped' unless NLHue::Disco.disco_started?
	end

	10.times do |time|
		EM.add_timer(time * 5) do
			puts "\n\n--- Starting discovery #{time}"
			NLHue::Disco.start_discovery(USER, 1)
		end

		# FIXME: A race condition exists that allows start_discovery
		# and do_disco as used here to start two running discovery
		# processes.  Maybe?  Maybe this was due to adding the disco_cb twice.
		EM.add_timer(time * 5 + 0.1) do
			puts "\n\n--- Forcing discovery"
			NLHue::Disco.do_disco if NLHue::Disco.disco_started?
		end

		EM.add_timer(time * 5 + 0.5) do
			puts "\n\n--- Stopping discovery shortly after starting #{time}"
			NLHue::Disco.stop_discovery
		end
	end

	EM.add_timer(30) do
		puts "\n\n--- Exiting"
		NLHue::Disco.stop_discovery
		EM.add_timer(1) do
			EM.stop_event_loop
		end
	end
end

puts "Available bridges count is #{avail}, should be 0" if avail != 0
