# Barebones asynchronous SSDP device discovery using EventMachine.
# Part of Nitrogen Logic's Ruby interface library for the Philips Hue.
# (C)2012 Mike Bourgeous

require 'socket'
require 'eventmachine'

module NLHue
	module SSDP
		SSDP_ADDR = '239.255.255.250'
		SSDP_PORT = 1900

		# Eventually calls the given block with a NLHue::SSDP::Response
		# for each matching device found on the network within timeout
		# seconds.  The block will be called with nil after the
		# timeout.
		def self.discover type='ssdp:all', timeout=5, &block
			raise 'A block must be given to discover().' unless block_given?

			con = EM::open_datagram_socket('0.0.0.0', 0, SSDPConnection, type, timeout, block)
			EM.add_timer(timeout) do
				con.close_connection
				EM.next_tick do
					yield nil
				end
			end

			# TODO: Structure this using EM::Deferrable instead?
		end

		# The HTTP response representing a service discovered by SSDP.
		class Response
			attr_reader :ip, :response, :headers

			def initialize ip, response
				@ip = ip
				@response = response
				@headers = {}

				response.split("\r\n\r\n", 2)[0].lines.each do |line|
					next unless line.include? ': '
					key, value = line.split(': ', 2)
					@headers[key.downcase] = value
				end
			end

			def to_s
				"#{@ip}:\n\t#{@response.lines.to_a.join("\t")}"
			end

			# Retrieves the value of a header, with case
			# insensitive matching.
			def [] header
				@headers[header.downcase]
			end
		end

		private
		# UDP connection used for SSDP by discover().
		class SSDPConnection < EM::Connection
			# type - the SSDP service type (used in the ST: field)
			# timeout - the number of seconds to wait for responses (used in the MX: field)
			# receiver is the block passed to discover().
			def initialize type, timeout, receiver
				super
				@type = type
				@timeout = timeout
				@receiver = receiver
				@msg = "M-SEARCH * HTTP/1.1\r\n" +
				"HOST: #{SSDP_ADDR}:#{SSDP_PORT}\r\n" +
				"MAN: ssdp:discover\r\n" +
				"MX: #{timeout.to_i}\r\n" +
				"ST: #{type}\r\n" +
				"\r\n"
			end

			def post_init
				send_datagram @msg, SSDP_ADDR, SSDP_PORT
			end

			def receive_data data
				port, ip = Socket.unpack_sockaddr_in(get_peername)
				@receiver.call Response.new(ip, data)
			end
		end
	end
end
