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
			if ssdp && ssdp['Location'].include?('description.xml') && ssdp['USN']
				serial = ssdp['USN'].gsub(/.*([0-9A-Fa-f]{12}).*/, '\1')
				unless devs.include?(ssdp.ip) && devs[ssdp.ip].serial == serial
					dev = Bridge.new ssdp.ip, serial
					dev.verify do |result|
						if result
							devs[ssdp.ip] = dev
							begin
								yield dev
							rescue => e
								puts "Error notifying block with discovered bridge: #{e}", e.backtrace
							end
						end
					end
				end
			end
		end

		# TODO: Allow discovery by serial number
	end
end
