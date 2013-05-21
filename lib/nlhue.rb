# Nitrogen Logic's Ruby interface library for the Philips Hue.
# (C)2013 Mike Bourgeous

# Dummy benchmarking method that may be overridden by library users.
unless methods.include?(:bench)
	def bench label, *args, &block
		yield
	end
end

# Logging method that may be overridden by library users.
unless methods.include?(:log)
	def log msg
		puts msg
	end
end

# Exception logging method that may be overridden by library users.
unless methods.include?(:log_e)
	def log_e e, msg=nil
		e ||= StandardError.new('No exception given to log')
		if msg
			puts "#{msg}: #{e}", e.backtrace
		else
			puts e, e.backtrace
		end
	end
end

require_relative 'nlhue/ssdp.rb'
require_relative 'nlhue/disco.rb'
require_relative 'nlhue/bridge.rb'
require_relative 'nlhue/light.rb'
require_relative 'nlhue/group.rb'
