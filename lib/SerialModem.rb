require 'SerialModem/version'
require 'serialport'

module SerialModem
  extend self

  def setup
    @serial_tty = @serial_tty_error = @serial_sp = nil
    @serial_replies = []
    @serial_codes = {}
    @serial_sms = {}
    @serial_ussd = nil
    @serial_ussd_results = {}
    @serial_mutex = Mutex.new
    @serial_thread = Thread.new {
      loop {
        read_reply
        sleep 0.5
      }
    }
  end

  def read_reply(wait = false)
    return unless check_tty
    @serial_mutex.synchronize {
      begin
        if wait
          begin
            @serial_replies.push @serial_sp.readline
          rescue EOFError => e
            log_msg :SerialModem, 'Waited for string, but got nothing'
          end
        end
        if not @serial_sp.eof?
          @serial_sp.readlines.each { |l|
            @serial_replies.push l.chomp
          }
        end
      rescue Exception => e
        puts "#{e.inspect}"
        puts "#{e.to_s}"
        puts e.backtrace
      end

      ret = []
      while m = @serial_replies.shift
        puts "Reply: #{m}"
        ret.push m
        if m =~ /\+[\w]{4}: /
          code, msg = m[1..4], m[7..-1]
          puts "found code #{code.inspect} - #{msg.inspect}"
          @serial_codes[code] = msg
          case code
            when /CMGL/
              dp msg
              sms_id, sms_flag, sms_number, sms_unknown, sms_date =
                  msg.scan(/(".*?"|[^",]\s*|,,)/).flatten
              dp sms_id
              dp ret.push @serial_replies.shift
              @serial_sms[sms_id] = [sms_flag, sms_number, sms_unknown, sms_date,
                                     ret.last]
            when /CUSD/
              dp msg
              if pdu = msg.match(/.*\"(.*)\".*/)
                dp pdu.inspect
                ussd_store_result(pdu_to_ussd(pdu[1]))
              end
            when /CMTI/
              # Probably a message or so - '+CMTI: "ME",0' is a new message
          end
        end
      end
      ret
    }
  end

  def modem_send(str)
    return unless check_tty
    ddputs(3) { "Sending string #{str} to modem" }
    @serial_sp.write("#{str}\r\n")
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

  def ussd_send(str, check = false)
    if @serial_ussd
      if check
        raise 'USSDinprogress'
      else
        @serial_ussd = nil
      end
    end
    str =~ /^\*.*\#$/ ? str_send = str : str_send = "*#{str}#"
    ddputs(3) { "Sending ussd-string #{str_send}" }
    @serial_ussd = str_send
    modem_send("AT+CUSD=1,\"#{ussd_to_pdu(str_send)}\"")
  end

  def ussd_store_result(str)
    cmd = @serial_ussd
    @serial_ussd_results[@serial_ussd] = str
    @serial_ussd = nil
    dp "#{cmd}: #{str}"
  end

  def ussd_fetch(str)
    str =~ /^\*.*\#$/ ? str_rcvd = "*#{str}#" : str_rcvd = str
    @serial_ussd_results.has_key? str_rcvd ? @serial_ussd_results[str_rcvd] : nil
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
    if @serial_sms.has_key? number
      modem_send("AT+CMGD=#{number}")
      @serial_sms.delete number
    end
  end

  def get_operator
    modem_send('AT+COPS=3,0')
    modem_send('AT+COPS?')
    if @serial_codes.has_key? 'COPS'
      @serial_codes['COPS'].scan(/(".*?"|[^",]\s*|,,)/)[2]
    end
  end

  def set_connection_type(net)

  end

  def traffic_statistics

  end

  def init_modem
    %w( ATZ
    AT+CNMI=0,0,0,0,0
    AT+CPMS="SM","SM","SM"
    AT+CFUN=1
    AT+CMGF=1 ).each { |at| modem_send(at) }
  end

  def check_tty
    check_presence

    if !@serial_sp && @serial_tty
      if File.exists? @serial_tty
        log_msg :SerialModem, 'connecting modem'
        @serial_sp = SerialPort.new(@serial_tty, 115200)
        @serial_sp.read_timeout = 500
        init_modem
      end
    else
      if @serial_tty && !File.exists?(@serial_tty)
        log_msg :SerialModem, 'disconnecting modem'
        @serial_sp.close
        @serial_sp = nil
        @serial_ussd = nil
        if File.exists? @serial_tty_error
          log_msg :SerialModem, 'resetting modem'
          %w( rmmod modprobe ).each { |cmd| System.run_bool("#{cmd} option") }
        end
      end
    end
    @serial_sp
  end

  def check_presence
    @serial_tty and File.exists?(@serial_tty) and return
    case System.run_str('lsusb')
      when /12d1:1506/, /12d1:14ac/, /12d1:1c05/
        log_msg :SerialModem, 'Found 3G-modem with ttyUSB0-ttyUSB2'
        @serial_tty_error = '/dev/ttyUSB3'
        @serial_tty = '/dev/ttyUSB2'
      when /airtel-modem/
        log_msg :SerialModem, 'Found 3G-modem with ttyUSB0-ttyUSB4'
        @serial_tty_error = '/dev/ttyUSB5'
        @serial_tty = '/dev/ttyUSB4'
      else
        @serial_tty = @serial_tty_error = nil
    end
  end
end
