#!/usr/bin/env ruby
require 'bundler/setup'
require 'test/unit'
require 'fileutils'

DEBUG_LVL=3

require 'serial_modem'

tests = Dir.glob('sm_*.rb')
tests = %w( receive )

$LOAD_PATH.push '.'
tests.each { |t|
  begin
    require "sm_#{t}"
  rescue LoadError => e
    require t
  end
}
