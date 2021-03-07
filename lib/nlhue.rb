# Nitrogen Logic's Ruby interface library for the Philips Hue.
# (C)2013 Mike Bourgeous

module NLHue
  module Log
    @@log_block = nil
    @@log_e_block = nil
    @@bench_block = nil

    # Pass a block that accepts a message to log, or pass nil to restore
    # default logging.
    def self.on_log(&block)
      @@log_block = block
    end

    # Pass a block that accepts an exception and an optional message to log, or
    # pass nil to restore default exception logging.
    def self.on_log_e(&block)
      @@log_e_block = block
    end

    # Pass a block to be called
    def self.on_bench(&block)
      @@bench_block = block
    end

    # Dummy benchmarking method that may be overridden by library users.
    def bench(label, *args, &block)
      if @@bench_block
        @@bench_block.call(label, *args, &block)
      else
        yield
      end
    end

    # Logging method that may be overridden by library users.
    def log(msg)
      if @@log_block
        @@log_block.call(msg)
      else
        puts msg
      end
    end

    # Exception logging method that may be overridden by library users using
    # the on_log_e method.
    def log_e(e, msg=nil)
      if @@log_e_block
        @@log_e_block.call(e, msg)
      else
        e ||= StandardError.new('No exception given to log')
        if msg
          log "#{msg}: #{e}", e.backtrace
        else
          log e, e.backtrace
        end
      end
    end
  end

  include Log
  extend Log
end

require_relative 'nlhue/ssdp'
require_relative 'nlhue/disco'
require_relative 'nlhue/bridge'
require_relative 'nlhue/target'
require_relative 'nlhue/light'
require_relative 'nlhue/group'
require_relative 'nlhue/scene'
