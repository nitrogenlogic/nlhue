#!/usr/bin/env ruby
# Makes sure log, log_e, and bench can be overridden.
# (C)2013 Mike Bourgeous

require_relative '../lib/nlhue'

NLHue::Log.on_log do |*args|
  puts "OK: Log overridden #{args}"
end

NLHue::Log.on_log_e do |*args|
  puts "OK: Log_e overridden #{args}"
end

NLHue::Log.on_bench do |*args, &block|
  puts "Benchmark overridden #{args}"
  block.call(true)
end

NLHue.log "successfully (not if at start of line)"
NLHue.log_e StandardError.new('an error'), 'indeed (not if at start of line)'
NLHue.bench 'test bench' do |*args|
	raise 'Not overridden' unless args[0] == true
end
