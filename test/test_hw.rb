#!/bin/env ruby
#$LOAD_PATH.push '../lib'
DEBUG_LVL=5

require 'serialmodem'
include SerialModem

setup_modem nil
check_presence
#set_connection_type '2go'
#sleep 10
ussd_send('*128#')
sleep 5
#set_connection_type '3g'
#sleep 10
#ussd_send('*128#')
#sleep 10
#ussd_send('*128#')
#sleep 10
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