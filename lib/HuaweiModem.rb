require 'HuaweiModem/version'
require 'serialport'

module HuaweiModem
  extend self

  def setup_modem
    @sp = SerialPort.new('/dev/ttyUSB0', 115200)
    @sp.read_timeout = 100
    @huawei_replies = []
    @huawei_mutex = Mutex.new
    @huawei_thread = Thread.new {
      loop {
        read_reply
        sleep 1
      }
    }
  end

  def read_reply
    if not @sp.eof?
      @sp.readlines.each { |l|
        @huawei_mutex.synchronize {
          @huawei_replies.push l.chomp
        }
        puts l.chomp
      }
    end
  end

  def send_modem(str)
    @sp.write("#{str}\r\n")
  end

  def switch_to_hilink
    send_modem('AT^U2DIAG=119')
  end

  def save_modem
    send_modem('AT^U2DIAG=0')
  end

  def ussd_to_pdu(str)
    str.unpack('b*').join.scan(/.{8}/).map { |s| s[0..6] }.join.
        scan(/.{1,8}/).map { |s| [s].pack('b*').unpack('H*')[0].upcase }.join
  end

  def pdu_to_ussd(str)
    [str].pack('H*').unpack('b*').join.scan(/.{7}/).
        map { |s| [s+"0"].pack('b*') }.join
  end

  def send_ussd(str)
    send_modem("AT+CUSD=1,\"#{ussd_to_pdu(str)}\"")
  end

  def send_sms(number, msg)
    send_modem('AT+CMGF=1')
    send_modem("AT+CMGS=\"#{number}\"")
    send_modem("#{msg}\x1a")
  end

  def read_sms(number=nil)
    send_modem('AT+CMGL="ALL"')
  end
end
