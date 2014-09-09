#!/bin/env ruby
$LOAD_PATH.push '../lib'

require 'HuaweiModem'

HuaweiModem::setup_modem
puts HuaweiModem::send_ussd('*100#')
sleep 5
puts HuaweiModem::send_modem('atz')
sleep 10