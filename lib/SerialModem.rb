require 'SerialModem/version'
require 'serialport'
require 'helperclasses'

module SerialModem
  attr_accessor :serial_sms_new, :serial_sms_to_delete, :serial_sms
  extend self
  include HelperClasses
  include HelperClasses::DPuts
  extend HelperClasses::DPuts

  def setup_modem(dev)
    @serial_tty = @serial_tty_error = @serial_sp = nil
    @serial_replies = []
    @serial_codes = {}
    @serial_sms = {}
    @serial_sms_new = []
    @serial_sms_to_delete = []
    @serial_ussd = []
    @serial_ussd_last = Time.now
    @serial_ussd_timeout = 30
    @serial_ussd_results = {}
    @serial_mutex = Mutex.new
    check_presence and init_modem
    @serial_thread = Thread.new {
      loop {
        begin
          dputs(5) { 'Reading out modem' }
          if read_reply.length == 0
            @serial_sms_to_delete.each { |id|
              log_msg :SerialModem, "Deleting sms #{id} afterwards"
              sms_delete(id)
            }
            @serial_sms_to_delete = []
          end

          dputs(4) { (Time.now - @serial_ussd_last).to_s }
          if (Time.now - @serial_ussd_last > @serial_ussd_timeout) &&
              (@serial_ussd.length > 0)
            log_msg :SerialModem, "Re-sending #{@serial_ussd.first}"
            ussd_send_now
          end
          sleep 0.5
        rescue IOError
          log_msg :SerialModem, 'IOError - killing modem'
          return
        rescue Exception => e
          puts "#{e.inspect}"
          puts "#{e.to_s}"
          puts e.backtrace
        end
      }
    }
  end

  def read_reply(wait = nil)
    raise IOError.new('NoModemHere') unless check_tty
    ret = []
    begin
      @serial_mutex.synchronize {
        while !@serial_sp.eof? || wait
          begin
            @serial_replies.push rep = @serial_sp.readline.chomp
            break if rep == wait
          rescue EOFError => e
            dputs(4) { 'Waited for string, but got nothing' }
            break
          end
        end
      }

      while m = @serial_replies.shift
        next if (m == '' || m =~ /^\^/)
        dputs(3) { "Reply: #{m}" }
        ret.push m
        if m =~ /\+[\w]{4}: /
          code, msg = m[1..4], m[7..-1]
          dputs(2) { "found code #{code.inspect} - #{msg.inspect}" }
          @serial_codes[code] = msg
          case code
            when /CMGL/
              sms_id, sms_flag, sms_number, sms_unknown, sms_date =
                  msg.scan(/(".*?"|[^",]+\s*|,,)/).flatten
              ret.push @serial_replies.shift
              @serial_sms[sms_id] = [sms_flag, sms_number, sms_unknown, sms_date,
                                     ret.last]
              @serial_sms_new.each { |s|
                s.call(@serial_sms, sms_id)
              }
            when /CUSD/
              dp 'cusd'
              if pdu = msg.match(/.*\"(.*)\".*/)
                dp 'ussd_store'
                ussd_store_result(pdu_to_ussd(pdu[1]))
              end
            when /CMTI/
              if msg =~ /^.CMTI: .ME.,/
                dputs(2) { "I think I got a new message: #{msg}" }
                sms_scan
              end
            # Probably a message or so - '+CMTI: "ME",0' is a new message
          end
        end
      end
    rescue IOError => e
      raise e
    rescue Exception => e
      puts "#{e.inspect}"
      puts "#{e.to_s}"
      puts e.backtrace
    end
    ret
  end

  def modem_send(str, reply = true)
    #dputs_func
    return unless check_tty
    dputs(3) { "Sending string #{str} to modem" }
    check = false
    @serial_mutex.synchronize {
      begin
        @serial_sp.write("#{str}\r\n")
      rescue Errno::EIO => e
        log_msg :SerialModem, "Couldn't write to device"
        check = true
      end
    }
    check and check_presence
    read_reply(reply)
    #read_reply
  end

  def switch_to_hilink
    modem_send('AT^U2DIAG=119', 'OK')
  end

  def save_modem
    modem_send('AT^U2DIAG=0', 'OK')
  end

  def ussd_to_pdu(str)
    str.unpack('b*').join.scan(/.{8}/).map { |s| s[0..6] }.join.
        scan(/.{1,8}/).map { |s| [s].pack('b*').unpack('H*')[0].upcase }.join
  end

  def pdu_to_ussd(str)
    [str].pack('H*').unpack('b*').join.scan(/.{7}/).
        map { |s| [s+"0"].pack('b*') }.join
  end

  def ussd_send_now
    return unless @serial_ussd.length > 0
    str_send = @serial_ussd.first
    dputs(3) { "Sending ussd-string #{str_send} with add of #{@ussd_add} "+
        "and queue #{@serial_ussd}" }
    @serial_ussd_last = Time.now
    modem_send("AT+CUSD=1,\"#{ussd_to_pdu(str_send)}\"#{@ussd_add}", 'OK')
  end

  def ussd_send(str)
    dputs(3) { "Sending ussd-code #{str}" }
    @serial_ussd.push str
    @serial_ussd.length == 1 and ussd_send_now
  end

  def ussd_store_result(str)
    dp "store: #{@serial_ussd.inspect}"
    return nil unless @serial_ussd.length > 0
    code = @serial_ussd.shift
    dputs(2) { "Got USSD-reply for #{code}: #{str}" }
    @serial_ussd_results[code] = str
    ussd_send_now
  end

  def ussd_fetch(str)
    return nil unless @serial_ussd_results
    dputs(3) { "Fetching str #{str} - #{@serial_ussd_results.inspect}" }
    @serial_ussd_results.has_key?(str) ? @serial_ussd_results[str] : nil
  end

  def sms_send(number, msg)
    modem_send('AT+CMGF=1', 'OK')
    modem_send("AT+CMGS=\"#{number}\"")
    modem_send("#{msg}\x1a", 'OK')
  end

  def sms_scan
    modem_send('AT+CMGF=1', 'OK')
    modem_send('AT+CMGL="ALL"', 'OK')
  end

  def sms_delete(number)
    dputs(2) { "Asking to delete #{number} from #{@serial_sms.inspect}" }
    if @serial_sms.has_key? number
      dputs(3) { "Deleting #{number}" }
      modem_send("AT+CMGD=#{number}", 'OK')
      @serial_sms.delete number
    end
  end

  def get_operator
    modem_send('AT+COPS=3,0', 'OK')
    modem_send('AT+COPS?', 'OK')
    (1..6).each {
      if @serial_codes.has_key? 'COPS'
        return '' if @serial_codes['COPS'] == '0'
        return @serial_codes['COPS'].scan(/".*?"|[^",]\s*|,,/)[2].gsub(/"/, '')
      end
      sleep 0.5
    }
    return ''
  end

  def set_connection_type(net, modem = :e303)
    # According to https://wiki.archlinux.org/index.php/3G_and_GPRS_modems_with_pppd
    cmds = {e303: {c3go: '14,2,3FFFFFFF,0,2', c3g: '2,2,3FFFFFFF,0,2',
                   c2go: '13,1,3FFFFFFF,0,2', c2g: '2,1,3FFFFFFF,0,2'}}
    modem_send "AT^SYSCFG=#{cmds[modem]["c#{net}".to_sym]}", 'OK'
  end

  def traffic_statistics

  end

  def init_modem
    %w( ATZ
    AT+CNMI=0,0,0,0,0
    AT+CPMS="SM","SM","SM"
    AT+CFUN=1
    AT+CMGF=1 ).each { |at| modem_send(at, 'OK') }
    set_connection_type '3g'
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
      if @serial_sp &&
          (!@serial_tty||(@serial_tty && !File.exists?(@serial_tty)))
        log_msg :SerialModem, 'disconnecting modem'
        @serial_sp.close
        @serial_sp = nil
        @serial_ussd = nil
        if @serial_tty_error && File.exists?(@serial_tty_error)
          log_msg :SerialModem, 'resetting modem'
          %w( rmmod modprobe ).each { |cmd| System.run_bool("#{cmd} option") }
        end
      end
    end
    @serial_sp
  end

  def check_presence
    @serial_mutex.synchronize {
      @serial_tty and File.exists?(@serial_tty) and return
      case lsusb = System.run_str('lsusb')
        when /12d1:1506/, /12d1:14ac/, /12d1:1c05/
          log_msg :SerialModem, 'Found 3G-modem with ttyUSB0-ttyUSB2'
          @serial_tty_error = '/dev/ttyUSB3'
          @serial_tty = '/dev/ttyUSB2'
          @ussd_add = (lsusb =~ /12d1:14ac/) ? ',15' : ''
        when /airtel-modem/
          log_msg :SerialModem, 'Found 3G-modem with ttyUSB0-ttyUSB4'
          @serial_tty_error = '/dev/ttyUSB5'
          @serial_tty = '/dev/ttyUSB4'
          @ussd_add = ''
        else
          @serial_tty = @serial_tty_error = nil
      end
    }
  end

  def kill
    if @serial_thread
      if @serial_thread.alive?
        dputs(3) { 'Killing thread' }
        @serial_thread.kill
        dputs(3) { 'Joining thread' }
        @serial_thread.join
      end
    end
    @serial_sp and @serial_sp = nil
    dputs(3) { 'SerialModem killed' }
  end
end
