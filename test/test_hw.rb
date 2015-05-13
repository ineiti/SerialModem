#!/bin/env ruby
#$LOAD_PATH.push '../lib'
DEBUG_LVL=5

require 'serial_modem'
include SerialModem

def main
  test_send_ussd
end

def test_remove
  setup_modem
  check_presence
  sleep 3
  kill
  sleep 5
  reload_option
end

def test_send_ussd
  setup_modem
  #check_presence
  ussd_send('*100#')
  sleep 5
  #dp 'done'
end

def test_old
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
end

main