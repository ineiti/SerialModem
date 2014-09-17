#!/bin/env ruby
$LOAD_PATH.push '../lib'

require 'serialmodem'
include SerialModem


modem_setup
puts get_operator
#sleep 1
#ussd_send('*128#')
#sms_send('93999699', 'SMS from Dreamplug')
#sms_send('100', 'internet')
#sms_scan
#sleep 10
#ussd_send('*100#')
#sms_scan
#@huawei_sms.each{|k,v| puts "#{k}: #{v.inspect}"}
#sms_scan
#sms_delete( 0 )
#sms_scan
#sleep 10
#puts SerialModem::send_modem('atz')
#sleep 10