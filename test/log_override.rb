#!/usr/bin/env ruby
# Makes sure log, log_e, and bench can be overridden.
# (C)2013 Mike Bourgeous

def log *args
	puts "OK: Log overridden #{args}"
end

def log_e *args
	puts "OK: Log_e overridden #{args}"
end

def bench *args, &block
	puts "Benchmark overridden #{args}"
	yield true
end

require_relative '../lib/nlhue'

log "successfully (not if at start of line)"
log_e StandardError.new('an error'), 'indeed (not if at start of line)'
bench 'test bench' do |*args|
	raise 'Not overridden' unless args[0] == true
end
