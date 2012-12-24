# A class representing a Hue bridge.
# (C)2012 Mike Bourgeous

require 'eventmachine'
require 'em/protocols/httpclient'
require 'rexml/document'
require 'json'

module NLHue
	class LinkButtonError < StandardError
		def initialize msg="Press the bridge's link button."
			super msg
		end
	end

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

		# Attempts to register the given username with the Bridge.  The
		# block will be called with true and the result if registration
		# succeeds, false and an exception if not.
		def register username, devicetype, &block
			raise 'Username must be >= 10 characters' unless username.to_s.length >= 10
			raise 'Spaces are not permitted in usernames' if username =~ /[[:space:]]/

			msg = %Q{{"username":#{username.to_json},"devicetype":#{devicetype.to_json}}}
			puts "Sending #{msg}"
			post '/api', msg, do |response|
				puts "Register response: #{response.inspect}" # XXX

				result_msgs = []
				status = true
				result = response
				if response.is_a?(Hash) && response[:status] == 200
					j = JSON.parse response[:content]
					status = true
					j.each do |v|
						if v['error']; then
							status = false
							result_msgs << v['error']['description']
						end
					end

					# TODO: Handle an invalid username that results in a new username being created

					# FIXME: I don't like this error handling
					unless status
						if result_msgs.include?('link button not pressed')
							result = LinkButtonError.new
						else
							result = StandardError.new(msg.join(', '))
						end
					end
				else
					status = false
					result = StandardError.new response
				end

				yield status, result
			end
		end

		# Makes a GET request to the given path, timing out after the
		# given number of seconds, and calling the given block with a
		# hash containing :content, :headers, and :status, or just
		# false if there was an error.
		def get path, timeout=5, &block
			# FIXME: Use em-http-request instead of HttpClient,
			# which returns an empty :content field
			request 'GET', path, nil, nil, timeout, &block
		end

		# Makes a POST request to the given path, with the given data
		# and content type, timing out after the given number of
		# seconds, and calling the given block with a hash containing
		# :content, :headers, and :status, or just false if there was
		# an error.
		def post path, data, content_type='application/json;charset=utf-8', timeout=5, &block
			request 'POST', path, data, content_type, timeout, &block
		end

		# Makes a PUT request to the given path, with the given data
		# and content type, timing out after the given number of
		# seconds, and calling the given block with a hash containing
		# :content, :headers, and :status, or just false if there was
		# an error.
		def put path, data, content_type='application/json;charset=utf-8', timeout=5, &block
			request 'PUT', path, data, content_type, timeout, &block
		end

		# Makes a DELETE request to the given path, timing out after
		# the given number of seconds, and calling the given block with
		# a hash containing :content, :headers, and :status, or just
		# false if there was an error.
		def delete path, timeout=5, &block
			request 'DELETE', path, nil, nil, timeout, &block
		end

		# Makes a request of the given type to the given path, using
		# the given data and content type for e.g. PUT and POST.  The
		# request will time out after timeout seconds.  The given block
		# will be called with a hash containing :content, :headers, and
		# :status if a response was received, or just false on error.
		def request verb, path, data=nil, content_type='application/json;charset=utf-8', timeout=5, &block
			raise 'A block must be given.' unless block_given?
			req = EM::P::HttpClient.request(
				verb: verb,
				host: @addr,
				request: path,
				content: data,
				contenttype: content_type,
			)
			req.callback {|response|
				yield response
			}
			req.errback {
				req.close_connection # For timeout
				yield false
			}
			req.timeout 5
		end
	end
end
