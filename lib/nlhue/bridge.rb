# A class representing a Hue bridge.
# (C)2012 Mike Bourgeous

require 'eventmachine'
require 'em/protocols/httpclient'
require 'rexml/document'

module NLHue
	# A class representing a Hue bridge.  A Bridge object may not refer to
	# an actual Hue bridge if verify() hasn't succeeded.
	class Bridge
		# addr - The IP address or hostname of the Hue bridge.
		def initialize addr
			@addr = addr
			@verified = false
		end

		# Calls the given block with true or false if verification by
		# description.xml succeeds or fails.  If verification has
		# already been performed, the block will be called immediately
		# with true.
		def verify &block
			if @verified
				yield true
				return true
			end

			get '/description.xml' do |result|
				puts "Description result: #{result.inspect}" # XXX
				if result.is_a?(Hash) && result[:status] == 200
					@desc = REXML::Document.new result[:content]
					@desc.write($stdout, 4, true) # XXX
					@desc.elements.each("modelName") do |el|
						puts "modelName: #{el.text}" # XXX
						
						if el.text.include? 'Philips hue'
							@verified = true
						end
					end
				end

				yield @verified
			end
		end

		# Makes a get request to the given path, timing out after the
		# given number of seconds, and calling the given block with a
		# hash containing :content, :headers, and :status, or just
		# false if there was an error.
		def get path, timeout=5, &block
			# FIXME: Use em-http-request instead of HttpClient,
			# which returns an empty :content field
			req = EM::P::HttpClient.request(
				verb: 'GET',
				host: @addr,
				request: path
			)
			req.callback {|response|
				yield response
			}
			req.errback {
				req.close_connection
				yield false
			}
			req.timeout 5
		end
	end
end
