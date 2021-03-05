#!/usr/bin/env ruby
# Recalls a random scene on all bridges found on the network.
# (C)2015 Mike Bourgeous

def log msg
	puts "#{Time.now.strftime('%Y-%m-%d %H:%M:%S.%6N %z')} - #{msg}"
	STDOUT.flush
end

require_relative '../lib/nlhue'

USER = ENV['HUE_USER'] || 'testing1234'

EM.run do
	NLHue::Bridge.add_bridge_callback do |bridge, status|
		log "Bridge event: #{bridge} is now #{status ? 'available' : 'unavailable'}"
	end

	NLHue::Disco.send_discovery(3) do |br|
		br.username = USER
		br.update do |status, result|
			br.scenes.each do |id, scene|
				log "Found #{scene} on #{br.serial}"
			end

			EM.add_timer(0.5) do
				log_e result if result.is_a? Exception

				if ARGV[0]
					scene = br.find_scene(ARGV[0])
				else
					scene = br.scenes.values.sample
				end

				if scene
					log "\e[34mRecalling \e[1m#{scene}\e[0m"
					br.groups[0].recall_scene(scene) do |*result|
						log "Scene recall result: #{result.inspect}"
					end
				else
					log "\e[31mNo matching scene found for \e[1m#{ARGV[0] || br.serial}\e[0m"
				end
			end
		end
	end
	EM.add_timer(4) do
		EM.stop_event_loop
	end
end
