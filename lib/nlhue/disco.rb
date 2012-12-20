# Discovery of Hue hubs using SSDP.
# (C)2012 Mike Bourgeous

module NLHue
	# Yields an SSDP response for each Hue hub found on the network.
	# Responses may come for timeout seconds after this function is called.
	def self.discover timeout=3,&block
		# Even though we put 'upnp:rootdevice' in the ST: header, the
		# Hue hub sends multiple matching and non-matching responses.
		# We'll use a hash to track which IP addresses we've seen.
		devs = {}

		NLHue::SSDP.discover 'upnp:rootdevice' do |response|
			if response && response['Location'].include?('description.xml')
				yield response unless devs.include? response.ip
				devs[response.ip] = response
			end
			# TODO: Verify description.xml with a deferred HTTP request
		end

		# TODO: Add a Hue class, allow discovery by serial number,
		# return Hue instead of Response.
	end
end
