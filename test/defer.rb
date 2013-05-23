#!/usr/bin/env ruby1.9.1
# Tests repeated deferred color changes to all lights on all bridges.
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

			count = 0
			light_proc = proc {
				count += 1
				puts "\n\n"
				log "==================== LIGHT TICK #{count} ===================="
				br.lights.each_value do |light|
					log "Setting values on #{light}"
					light.defer
					light.on!
					light.bri = 255
					light.hue = rand(360)
					light.sat = rand(25) + 230
					light.transitiontime = 1

					count2 = count
					light.submit do |status, result|
						log "Finished sending to #{light} for #{count2}"
					end
				end
			}

			timer1 = EM.add_periodic_timer 0.95, light_proc

			EM.add_timer(10) do
				puts "Switching to 0.35s updates"
				timer1.cancel
				timer1 = EM.add_periodic_timer 0.35, light_proc
			end

			EM.add_timer(20) do
				puts "Switching to 0.1s updates"
				timer1.cancel
				timer1 = EM.add_periodic_timer 0.1, light_proc
			end

			EM.add_timer(26) do
				puts "Switching to 0.15s updates"
				timer1.cancel
				timer1 = EM.add_periodic_timer 0.15, light_proc
			end

			EM.add_timer(33) do
				puts "Swithing to 0.7s updates"
				timer1.cancel
				timer1 = EM.add_periodic_timer 0.7, light_proc
			end
		end
	end
	EM.add_timer(45) do
		EM.stop_event_loop
	end
end