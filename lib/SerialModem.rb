require 'SerialModem/version'
require 'serialport'

module SerialModem
  extend self

  def setup
    @huawei_sp = SerialPort.new('/dev/ttyUSB2', 115200)
    @huawei_sp.read_timeout = 100
    @huawei_replies = []
    @huawei_codes = {}
    @huawei_sms = {}
    @huawei_ussd = []
    @huawei_ussd_results = {}
    @huawei_mutex = Mutex.new
    @huawei_thread = Thread.new {
      loop {
        read_reply
        sleep 0.5
      }
    }
    modem_send('atz')
  end

  def read_reply(wait = false)
    @huawei_mutex.synchronize {
      begin
        if wait
          begin
            @huawei_replies.push @huawei_sp.readline
          rescue EOFError => e
            log_msg :SerialModem, 'Waited for string, but got nothing'
          end
        end
        if not @huawei_sp.eof?
          @huawei_sp.readlines.each { |l|
            @huawei_replies.push l.chomp
          }
        end
      rescue Exception => e
        puts "#{e.inspect}"
        puts "#{e.to_s}"
        puts e.backtrace
      end

      ret = []
      while m = @huawei_replies.shift
        #puts "Reply: #{m}"
        ret.push m
        if m =~ /\+[\w]{4}: /
          code, msg = m[1..4], m[7..-1]
          #puts "found code #{code} - #{msg}"
          @huawei_codes[code] = msg
          case code
            when /CMGL/
              dp msg
              sms_id, sms_flag, sms_number, sms_unknown, sms_data =
                  msg.scan(/(".*?"|[^",]\s*|,,)/).flatten
              dp sms_id
              ret.push @huawei_replies.shift
              @huawei_sms[sms_id] = [sms_flag, sms_number, sms_unknown, sms_data,
                                     ret.last]
            when /CUSD/
              if pdu = msg.match(/.*\"(.*)\".*/)
                ussd_result(pdu_to_ussd(pdu[1]))
              end
          end
        end
      end
      ret
    }
  end

  def modem_send(str)
    @huawei_sp.write("#{str}\r\n")
    read_reply(true)
  end

  def switch_to_hilink
    modem_send('AT^U2DIAG=119')
  end

  def save_modem
    modem_send('AT^U2DIAG=0')
  end

  def ussd_to_pdu(str)
    str.unpack('b*').join.scan(/.{8}/).map { |s| s[0..6] }.join.
        scan(/.{1,8}/).map { |s| [s].pack('b*').unpack('H*')[0].upcase }.join
  end

  def pdu_to_ussd(str)
    [str].pack('H*').unpack('b*').join.scan(/.{7}/).
        map { |s| [s+"0"].pack('b*') }.join
  end

  def ussd_send(str)
    raise 'USSDinprogress' if @huawei_ussd.size > 0
    @huawei_ussd.push str
    modem_send("AT+CUSD=1,\"#{ussd_to_pdu(str)}\"")
  end

  def ussd_result(str)
    cmd = @huawei_ussd.pop
    @huawei_ussd_results[cmd] = str
    puts "#{cmd}: #{str}"
  end

  def sms_send(number, msg)
    modem_send('AT+CMGF=1')
    modem_send("AT+CMGS=\"#{number}\"")
    modem_send("#{msg}\x1a")
  end

  def sms_scan
    modem_send('AT+CMGF=1')
    modem_send('AT+CMGL="ALL"')
  end

  def sms_delete(number)
    if @huawei_sms.has_key? number
      modem_send("AT+CMGD=#{number}")
      @huawei_sms.delete number
    end
  end

  def get_operator
    modem_send('AT+COPS=3,0')
    modem_send('AT+COPS?')
    if @huawei_codes.has_key? 'COPS'
      @huawei_codes['COPS'].scan(/(".*?"|[^",]\s*|,,)/)[2]
    end
  end

  def set_connection_type(net)

  end

  def traffic_statistics

  end

end
