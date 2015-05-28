#!/usr/bin/env ruby
require 'thread'

$m = Mutex.new

def killme
  t.kill
  t.join
end

$t = Thread.new {
  $m.synchronize {
    loop do
      puts "In thread"
      sleep 1
      killme
    end
  }
}

sleep 2

$m.synchronize {
  puts "OK to synch here"
}
