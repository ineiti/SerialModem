require 'test/unit'
require 'serial_modem'

class SM_receive < Test::Unit::TestCase
  include SerialModem

  def setup
    setup_modem
  end

  def teardown

  end

  def test_receive_sms
    str = 'AT+CMGL="ALL"
+CMGL: 1,"REC UNREAD","192",,"15/06/24,09:14:06+04"
Souscription reussie:GPRS 3030. 10240MB valable 30 jours. Cout 50000F

OK'
    @serial_replies = str.split("\n")
    interpret_serial_reply
    assert_equal({'1' =>
                      {:flag => 'REC UNREAD',
                       :number => '192',
                       :unknown => '',
                       :date => '15/06/24,09:14:06+04',
                       :msg =>
                           'Souscription reussie:GPRS 3030. 10240MB valable 30 jours. Cout 50000F',
                       :id => '1'}}, @serial_sms)
  end

  def test_receive_two_sms
    str = 'AT+CMGL="ALL"
+CMGL: 0,"REC UNREAD","+121",,"15/06/24,21:20:01+04"
Cmd: stat1
+CMGL: 1,"REC UNREAD","+121",,"15/06/24,21:20:01+04"
Cmd: stat2

OK'
    @serial_replies = str.split("\n")
    interpret_serial_reply
    assert_equal({'0' =>
                      {:flag => 'REC UNREAD',
                       :number => '+121',
                       :unknown => '',
                       :date => '15/06/24,21:20:01+04',
                       :msg => 'Cmd: stat1',
                       :id => '0'},
                  '1' =>
                      {:flag => 'REC UNREAD',
                       :number => '+121',
                       :unknown => '',
                       :date => '15/06/24,21:20:01+04',
                       :msg => 'Cmd: stat2',
                       :id => '1'}}, @serial_sms)
  end
end
