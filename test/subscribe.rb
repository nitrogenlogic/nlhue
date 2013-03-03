#!/usr/bin/env ruby1.9.1
# Tests periodic bridge updates.
# (C)2012 Mike Bourgeous

require_relative '../lib/nlhue'

USER = ENV['HUE_USER'] || 'testing1234'

EM.run do
	NLHue.discover(3) do |br|
		br.username = USER

		count = 0
		br.add_update_callback do |status, result|
			if status
				count = count + 1
				puts "Bridge #{br.serial} updated #{count} times"
			else
				puts "Bridge #{br.serial} failed to update: #{result}"
			end
		end

		br.subscribe
	end
	EM.add_timer(10) do
		EM.stop_event_loop
	end
end