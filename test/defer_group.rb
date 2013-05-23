#!/usr/bin/env ruby1.9.1
# Tests repeated deferred color changes to group 0 on all bridges.  Group
# updates appear to be much slower, but better synchronized.
# (C)2013 Mike Bourgeous

def log msg
	puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S.%6N %z')} - #{msg}"
	STDOUT.flush
end

require_relative '../lib/nlhue'

USER = ENV['HUE_USER'] || 'testing1234'

EM.run do
	NLHue::Bridge.add_bridge_callback do |bridge, status|
		puts "Bridge event: #{bridge} is now #{status ? 'available' : 'unavailable'}"
	end

	NLHue::Disco.send_discovery(3) do |br|
		br.username = USER
		br.update do |status, result|
			log_e result if result.is_a? Exception
				
			group = br.groups[0]

			count = 0
			group_proc = proc {
				puts "\n\n"
				log "==================== GROUP TICK #{count} ===================="
				log "Setting values on #{group}"
				
				group ||= br.groups[0]
				next unless group

				group.defer
				group.on!
				group.bri = 255
				group.hue = count * 31
				group.sat = 255
				group.transitiontime = 0

				count2 = count
				group.submit do |status, result|
					log "Finished sending to #{group} for #{count2}"
				end
				count += 1
			}

			STDERR.puts "\n\n\n#{'='*80}\nSwitching to 1.15s updates\n#{'='*80}\n"
			timer1 = EM.add_periodic_timer 1.15, group_proc

			EM.add_timer(10) do
				STDERR.puts "\n\n\n#{'='*80}\nSwitching to 0.35s updates\n#{'='*80}\n"
				timer1.cancel
				timer1 = EM.add_periodic_timer 0.35, group_proc
			end

			EM.add_timer(20) do
				STDERR.puts "\n\n\n#{'='*80}\nSwitching to 0.05s updates\n#{'='*80}\n"
				timer1.cancel
				timer1 = EM.add_periodic_timer 0.05, group_proc
			end

			EM.add_timer(26) do
				STDERR.puts "\n\n\n#{'='*80}\nSwitching to 1.2s updates\n#{'='*80}\n"
				timer1.cancel
				timer1 = EM.add_periodic_timer 1.2, group_proc
			end

			EM.add_timer(33) do
				STDERR.puts "\n\n\n#{'='*80}\nSwitching to 0.7s updates\n#{'='*80}\n"
				timer1.cancel
				timer1 = EM.add_periodic_timer 0.7, group_proc
			end
		end
	end
	EM.add_timer(45) do
		EM.stop_event_loop
	end
end
