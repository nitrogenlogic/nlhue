# Discovery of Hue bridges using SSDP.
# (C)2013 Mike Bourgeous

module NLHue
	# Use #start_discovery and #stop_discovery for continuous bridge
	# discovery.  Use #send_discovery to perform discovery only once.
	module Disco
		# Number of times a bridge can be missing from discovery if not
		# subscribed (approx. 5*15=1.25min if interval is 15)
		MAX_BRIDGE_AGE = 5

		# Number of times a bridge can be missing from discovery if not
		# subscribed (approx. 100*15=25min if interval is 15).  This
		# number is higher than MAX_BRIDGE_AGE because update failures
		# (see MAX_BRIDGE_ERR) will detect an offline bridge, and
		# working bridges sometimes disappear from discovery.
		MAX_SUBSCRIBED_AGE = 100

		# Number of times a bridge can fail to update
		MAX_BRIDGE_ERR = 2

		# Bridges discovered on the network
		# [serial] => {
		# 	:bridge => NLHue::Bridge,
		# 	:age => [# of failed discos],
		# 	:errcount => [# of failed updates]
		# }
		@@bridges = {}

		@@disco_interval = 15
		@@disco_timer = nil
		@@disco_proc = nil
		@@disco_done_timer = nil
		@@disco_callbacks = []
		@@bridges_changed = false
		@@disco_running = false

		# Starts a timer that periodically discovers Hue bridges.  If
		# the username is specified, the Bridge objects' username will
		# be set before trying to update.
		# Using very short intervals may overload Hue bridges, causing
		# light and group commands to be delayed or erratic.
		def self.start_discovery username=nil, interval=15
			raise 'Discovery is already running' if @@disco_timer || @@disco_running
			raise 'Username must be a String' unless username.is_a? String
			raise 'Interval must be a number' unless interval.is_a? Numeric
			raise 'Interval must be >= 1' unless interval >= 1

			@@disco_interval = interval

			@@disco_proc = proc {
				@@disco_timer = nil
				@@disco_running = true

				notify_callbacks :start

				reset_disco_timer nil, 5
				send_discovery do |br|
					if br.is_a? NLHue::Bridge
						br.username = username if username
						br.update do |status, result|
							reset_disco_timer br
						end
					end
				end
			}

			do_disco
		end

		# Stops periodic Hue bridge discovery, removes all discovery
		# callbacks, and clears the list of bridges.
		def self.stop_discovery
			@@disco_timer.cancel if @@disco_timer
			@@disco_done_timer.cancel if @@disco_done_timer

			@@bridges.each do |serial, info|
				puts "Removing bridge #{serial} when stopping discovery" # XXX
				notify_callbacks :del, info[:bridge]
				info[:bridge].unsubscribe
			end
			if @@disco_done_timer
				notify_callbacks :end, !@@bridges.empty?
			end

			EM.next_tick do
				@@bridges.clear
				@@disco_timer = nil
				@@disco_done_timer = nil
				@@disco_proc = nil
				@@disco_running = false
				@@disco_callbacks.clear
			end
		end

		# Adds the given block to be called with discovery events.  The return
		# value may be passed to remove_disco_callback.
		#
		# The callback will be called with the following events:
		# :start - A discovery process has started.
		# :add, bridge - The given bridge was recently discovered.
		# :del, bridge - The given bridge was recently removed.  May be called
		# 		 even if no discovery process is running.
		# :end, true/false - A discovery process has ended, and whether there
		# 		     were changes to the list of bridges.
		def self.add_disco_callback cb=nil, &block
			raise 'No callback was given.' unless block_given? || cb
			raise 'Pass only a block or a Proc object, not both.' if block_given? && cb
			@@disco_callbacks << (cb || block)
			block
		end

		# Removes a discovery callback (call this with the return value from add_disco_callback)
		def self.remove_disco_callback callback
			@@disco_callbacks.delete callback
		end

		# Triggers a discovery process immediately (fails if #start_discovery
		# has not been called).
		def self.do_disco
			raise 'Call start_discovery() first.' unless @@disco_proc
			@@disco_timer.cancel if @@disco_timer
			@@disco_proc.call if @@disco_proc
		end

		# Indicates whether a discovery process is currently running.
		def self.disco_running?
			@@disco_running
		end

		# Returns an array of the bridges previously discovered on the
		# network.
		def self.bridges
			@@bridges.map do |serial, info|
				info[:bridge]
			end
		end

		# Returns a bridge with the given serial number, if present.
		def self.get_bridge serial
			serial = serial.downcase
			@@bridges[serial] && @@bridges[serial][:bridge]
		end

		# Gets the number of consecutive times a bridge has been
		# missing from discovery.
		def self.get_missing_count serial
			serial = serial.downcase
			@@bridges[serial] && @@bridges[serial][:age]
		end

		# Gets the number of consecutive times a bridge has failed to
		# update.  This value is only updated if the Bridge object's
		# subscribe or update methods are called.
		def self.get_error_count serial
			serial = serial.downcase
			@@bridges[serial] && @@bridges[serial][:errcount]
		end

		# Sends an SSDP discovery request, then yields an NLHue::Bridge
		# object for each Hue hub found on the network.  Responses may
		# come for more than timeout seconds after this function is
		# called.  Reuses Bridge objects from previously discovered
		# bridges, if any.
		def self.send_discovery timeout=3,&block
			# Even though we put 'upnp:rootdevice' in the ST: header, the
			# Hue hub sends multiple matching and non-matching responses.
			# We'll use a hash to track which IP addresses we've seen.
			devs = {}

			NLHue::SSDP.discover 'upnp:rootdevice' do |ssdp|
				if ssdp && ssdp['Location'].include?('description.xml') && ssdp['USN']
					serial = ssdp['USN'].gsub(/.*([0-9A-Fa-f]{12}).*/, '\1')
					unless devs.include?(ssdp.ip) && devs[ssdp.ip].serial == serial
						dev = @@bridges.include?(serial) ?
							@@bridges[serial][:bridge] :
							Bridge.new(ssdp.ip, serial)

						dev.addr = ssdp.ip unless dev.addr == ssdp.ip

						unless dev.verified?
							dev.verify do |result|
								if result
									devs[ssdp.ip] = dev
									begin
										yield dev
									rescue => e
										log_e e, "Error notifying block with discovered bridge #{serial}"
									end
								end
							end
						end
					end
				end
			end
		end

		private
		# Calls each discovery callback with the given parameters.
		def self.notify_callbacks *args
			bench "Notify Hue disco callbacks: #{args[0].inspect}" do
				@@disco_callbacks.each do |cb|
					begin
						cb.call *args
					rescue => e
						log_e e, "Error notifying Hue disco callback #{cb.inspect} about #{args[0]} event."
					end
				end
			end
		end

		# Adds the given bridge to the list of bridges (or resets the
		# timeout without adding a bridge if the bridge is nil).  After
		# timeout seconds, removes aged-out bridges from the internal
		# list of bridges and notifies disco callbacks that discovery
		# has ended.  Cancels any previous timeout.  This is called
		# each time a new bridge is discovered so that discovery ends
		# when no new bridges come in for timeout seconds.
		def self.reset_disco_timer br, timeout=2
			if br.is_a?(NLHue::Bridge)
				if @@bridges[br.serial]
					@@bridges[br.serial][:age] = 0
					@@bridges[br.serial][:errcount] = 0
				else
					@@bridges[br.serial] = { :bridge => br, :age => 0, :errcount => 0 }
					@@bridges_changed = true

					@@bridges[br.serial][:cb] = br.add_update_callback do |status, result|
						if status
							@@bridges[br.serial][:errcount] = 0
						else
							unless result.is_a? NLHue::NotRegisteredError
								@@bridges[br.serial][:errcount] += 1

								# Remove here instead of with *_AGE because
								# *_AGE is only checked once per disco.
								if @@bridges[br.serial][:errcount] > MAX_BRIDGE_ERR
									info = @@bridges[br.serial]
									@@bridges.delete br.serial
									br.remove_update_callback info[:cb]
									br.unsubscribe
									notify_bridge_removed br
									EM.next_tick do
										do_disco
									end
								end
							end
						end
					end

					notify_bridge_added br
				end
			end

			@@disco_done_timer.cancel if @@disco_done_timer
			@@disco_done_timer = EM::Timer.new(timeout) do
				update_bridges bridges
				@@disco_done_timer = nil

				EM.next_tick do
					@@disco_running = false
					notify_callbacks :end, @@bridges_changed
					@@disco_timer = EM::Timer.new(@@disco_interval, @@disco_proc) if @@disco_proc
					@@bridges_changed = false
				end
			end
		end

		# Adds new bridges to @@bridges, deletes aged-out bridges,
		# sends events to callbacks.  Called when the timer set by
		# #reset_disco_timer expires.
		def self.update_bridges bridges
			bench 'update_bridges' do
				@@bridges.each do |k, v|
					v[:age] += 1
				end

				bridges.each do |br|
				end

				@@bridges.select! do |k, br|
					age_limit = br[:bridge].subscribed? ? MAX_SUBSCRIBED_AGE : MAX_BRIDGE_AGE

					if br[:age] > age_limit
						log "Bridge #{br[:bridge].serial} missing from #{age_limit} rounds of discovery."
						@@bridges_changed = true
						br[:bridge].unsubscribe
						notify_bridge_removed br[:bridge]

						false
					else
						true
					end
				end
			end
		end

		# Notifies all disco callbacks that a bridge was added.
		def self.notify_bridge_added br
			EM.next_tick do
				notify_callbacks :add, br
			end
		end

		# Notifies all disco callbacks that a bridge was removed.
		def self.notify_bridge_removed br
			EM.next_tick do
				notify_callbacks :del, br
			end
		end
	end
end
