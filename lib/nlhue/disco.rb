# Discovery of Hue hubs using SSDP.
# (C)2012 Mike Bourgeous

module NLHue
	# Yields an NLHue::Bridge object for each Hue hub found on the network.
	# Responses may come for more than timeout seconds after this function
	# is called.
	def self.discover timeout=3,&block
		# Even though we put 'upnp:rootdevice' in the ST: header, the
		# Hue hub sends multiple matching and non-matching responses.
		# We'll use a hash to track which IP addresses we've seen.
		devs = {}

		NLHue::SSDP.discover 'upnp:rootdevice' do |ssdp|
			if ssdp && ssdp['Location'].include?('description.xml')
				unless devs.include? ssdp.ip
					dev = Bridge.new ssdp.ip
					dev.verify do |result|
						if result
							yield dev
							devs[ssdp.ip] = dev
						end
					end
				end
			end
		end

		# TODO: Allow discovery by serial number
	end
end
