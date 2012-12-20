#!/usr/bin/env ruby1.9.1
# Prints all responses received from an SSDP query.
# (C)2012 Mike Bourgeous

require_relative '../lib/nlhue'

EM.run do
	NLHue::SSDP.discover do |response|
		response ? puts(response) : EM.stop_event_loop
	end
end
