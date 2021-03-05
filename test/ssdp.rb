#!/usr/bin/env ruby
# Prints all responses received from an SSDP query.
# (C)2012 Mike Bourgeous

require_relative '../lib/nlhue'

EM.run do
	NLHue::SSDP.discover do |response|
		response ? puts(response, response.headers.inspect) : EM.stop_event_loop
	end
end
