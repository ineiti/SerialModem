#!/bin/env ruby
$LOAD_PATH.push '../lib'

require 'HuaweiModem'
include HuaweiModem

setup_modem
send_ussd('*100#')
#sleep 10
send_modem('AT+CMGF=1')
send_modem("AT+CMGS=\"93999699\"\n\rTest from DP at 8:26\x1a")
sleep 5
@huawei_replies.each { |r|
  puts "Parsing #{r}"
  case r
    when /\+CUSD:/
      puts pdu_to_ussd( r.match(/.*\"(.*)\".*/ )[1] )
  end
}
#puts HuaweiModem::send_modem('atz')
#sleep 10