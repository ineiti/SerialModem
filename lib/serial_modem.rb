require 'serialport'
require 'helper_classes'

module SerialModem
  DEBUG_LVL = 1
  attr_accessor :serial_sms_new, :serial_sms,
                :serial_ussd_new
  extend self
  include HelperClasses
  include HelperClasses::DPuts
  extend HelperClasses::DPuts

  def setup_modem(dev = nil)
    @serial_debug = false
    @serial_tty = @serial_tty_error = @serial_sp = nil
    @serial_replies = []
    @serial_codes = {}
    @serial_sms = {}
    # TODO: once serialmodem == class, change this into Observer
    @serial_sms_new = []
    @serial_sms_autoscan = 20
    @serial_sms_autoscan_last = Time.now
    @serial_ussd = []
    @serial_ussd_last = Time.now
    @serial_ussd_timeout = 30
    @serial_ussd_results = []
    @serial_ussd_results_max = 100
    # TODO: once serialmodem == class, change this into Observer
    @serial_ussd_new = []
    @serial_mutex_rcv = Mutex.new
    @serial_mutex_send = Mutex.new
    # Some Huawei-modems eat SMS once they send a +CMTI-message - this
    # turns off the CMTI-messages which slows down incoming SMS detection
    @serial_eats_sms = false
    setup_tty
  end

  def read_reply(wait = nil)
    @serial_debug and dputs_func
    raise IOError.new('NoModemHere') unless @serial_sp
    ret = []
    begin
      @serial_mutex_rcv.synchronize {
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
        @serial_debug and dputs_func
        next if (m == '' || m =~ /^\^/)
        dputs(3) { "Reply: #{m}" }
        ret.push m
        if m =~ /\+[\w]{4}: /
          code, msg = m[1..4], m[7..-1]
          dputs(3) { "found code #{code.inspect} - #{msg.inspect}" }
          @serial_codes[code] = msg
          case code
            when /CMGL/
              # Typical input from the modem:
              # "0,\"REC UNREAD\",\"+23599836457\",,\"15/04/08,17:12:21+04\""
              # Output desired:
              # ["0", "REC UNREAD", "+23599836457", "", "15/04/08,17:12:21+04"]
              id, flag, number, unknown, date =
                  msg.scan(/"(.*?)"|([^",]+)\s*|,,/).collect { |a, b| a.to_s + b.to_s }
              ret.push @serial_replies.shift
              sms_new(id, flag, number, date, ret.last, unknown)
            when /CUSD/
              if pdu = msg.match(/.*\"(.*)\".*/)
                ussd_received(pdu_to_ussd(pdu[1]))
              elsif msg == '2'
                #log_msg :serialmodem, 'Closed USSD.'
                #ussd_received('')
                #ussd_close
              else
                log_msg :serialmodem, "Unknown: CUSD - #{msg}"
              end
            when /CMTI/
              if msg =~ /^.ME.,/
                dputs(3) { "I think I got a new message: #{msg}" }
                sms_scan true
              else
                log_msg :serialmodem, "Unknown: CMTI - #{msg}"
              end
              @serial_eats_sms and modem_send('AT+CNMI=0,0,0,0,0', 'OK')
            # Probably a message or so - '+CMTI: "ME",0' is a new message
          end
        end
      end
    rescue IOError => e
      raise e
=begin
    rescue Exception => e
      puts "#{e.inspect}"
      puts "#{e.to_s}"
      puts e.backtrace
=end
    end
    ret
  end

  def sms_new(id, flag, number, date, msg, unknown = nil)
    sms = {flag: flag, number: number, unknown: unknown, date: date,
           msg: msg, id: id}
    @serial_sms[id.to_s] = sms
    if flag =~ /unread/i
      log_msg :SerialModem, "New SMS: #{sms.inspect}"
      rescue_all do
        @serial_sms_new.each { |s|
          s.call(sms)
        }
      end
    end
    sms
  end

  def modem_send(str, reply = true)
    return unless @serial_sp
    @serial_debug and dputs_func
    dputs(3) { "Sending string #{str} to modem" }
    @serial_mutex_send.synchronize {
      begin
        @serial_sp.write("#{str}\r\n")
      rescue Errno::EIO => e
        log_msg :SerialModem, "Couldn't write to device"
        kill
        return
      rescue Errno::ENODEV => e
        log_msg :SerialModem, 'Device is not here anymore'
        kill
        return
      end
    }
    read_reply(reply)
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
    @serial_ussd_last = Time.now
    if str_send
      #log_msg :SerialModem, "Sending ussd-string #{str_send} with add of #{@ussd_add} "+
                              "and queue #{@serial_ussd}"
      modem_send("AT+CUSD=1,\"#{ussd_to_pdu(str_send)}\"#{@ussd_add}", 'OK')
    else
      dputs(2) { 'Sending ussd-close' }
      @serial_ussd.shift
      ussd_close
    end
  end

  def ussd_close
    modem_send("AT+CUSD=2#{@ussd_add}", 'OK')
    @serial_ussd.length > 0 and ussd_send_now
  end

  def ussd_send(str)
    if str.class == String
      dputs(3) { "Sending ussd-code #{str}" }
      @serial_ussd.push str
      @serial_ussd.length == 1 and ussd_send_now
    elsif str.class == Array
      dputs(3) { "Sending menu-command #{str}" }
      @serial_ussd.concat str
      @serial_ussd.push nil
      @serial_ussd.length == str.length + 1 and ussd_send_now
    end
  end

  def ussd_store_result(str)
    if @serial_ussd.length > 0
      code = @serial_ussd.shift
      dputs(2) { "Got USSD-reply for #{code}: #{str}" }
      @serial_ussd_results.push(time: Time.now.strftime('%H:%M'),
                                code: code, result: str)
      @serial_ussd_results.shift([0, @serial_ussd_results.length -
                                       @serial_ussd_results_max].max)
      ussd_send_now
      code
    else
      #log_msg :serialmodem, "Got unasked code #{str}"
      'unknown'
    end
  end

  def ussd_received(str)
    code = ussd_store_result(str)
    dputs(2) { "Got result for #{code}: -#{str}-" }
    @serial_ussd_new.each { |s|
      s.call(code, str)
    }
  end

  def ussd_fetch(str)
    return nil unless @serial_ussd_results
    dputs(3) { "Fetching str #{str} - #{@serial_ussd_results.inspect}" }
    res = @serial_ussd_results.reverse.find { |u| u._code == str }
    res ? res._result : nil
  end

  def sms_send(number, msg)
    log_msg :SerialModem, "Sending SMS --#{msg.inspect}-- to --#{number.inspect}--"
    modem_send('AT+CMGF=1', 'OK')
    modem_send("AT+CMGS=\"#{number}\"")
    modem_send("#{msg}\x1a", 'OK')
  end

  def sms_scan(force = false)
    if force || (@serial_sms_autoscan > 0 &&
        Time.now - @serial_sms_autoscan_last > @serial_sms_autoscan)
      dputs(3) { 'Auto-scanning sms' }
      @serial_sms_autoscan_last = Time.now
      modem_send('AT+CMGF=1', 'OK')
      modem_send('AT+CMGL="ALL"', 'OK')
    end
  end

  def sms_delete(number)
    dputs(3) { "Asking to delete #{number} from #{@serial_sms.inspect}" }
    if @serial_sms.has_key? number.to_s
      dputs(3) { "Deleting #{number}" }
      modem_send("AT+CMGD=#{number}", 'OK')
      @serial_sms.delete number.to_s
    end
  end

  def get_operator
    modem_send('AT+COPS=3,0', 'OK')
    modem_send('AT+COPS?', 'OK')
    (1..6).each {
      if @serial_codes.has_key? 'COPS'
        return '' if @serial_codes['COPS'] == '0'
        @serial_eats_sms and modem_send('AT+CNMI=0,0,0,0,0', 'OK')
        op = @serial_codes['COPS'].scan(/".*?"|[^",]\s*|,,/)[2].gsub(/"/, '')
        dputs(2) { "Found operator-string #{op}" }
        return op
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
    @serial_eats_sms and modem_send('AT+CNMI=0,0,0,0,0', 'OK')
    set_connection_type '3g'
  end

  def setup_tty
    check_presence

    @serial_mutex_rcv.synchronize {
      if !@serial_sp && @serial_tty
        if File.exists? @serial_tty
          dputs(2){ 'setting up SerialPort'}
          @serial_sp = SerialPort.new(@serial_tty, 115200)
          @serial_sp.read_timeout = 500
        end
      elsif @serial_sp &&
          (!@serial_tty||(@serial_tty && !File.exists?(@serial_tty)))
        dputs(2){'disconnecting modem'}
        kill
      end
    }
    if @serial_sp
      dputs(2){'initialising modem'}
      init_modem
      start_serial_thread
      if !@serial_sp
        dputs(2){'Lost serial-connection while initialising - trying again'}
        kill
        reload_option
        setup_tty
        return
      end
      dputs(2){'finished connecting'}
    end
  end

  def check_presence
    @serial_mutex_rcv.synchronize {
      @serial_tty.to_s.length > 0 and File.exists?(@serial_tty) and return
      case lsusb = System.run_str('lsusb')
        when /12d1:1506/, /12d1:14ac/, /12d1:1c05/
          log_msg :SerialModem, 'Found 3G-modem with ttyUSB0-ttyUSB2'
          @serial_tty_error = '/dev/ttyUSB3'
          @serial_tty = '/dev/ttyUSB2'
          @ussd_add = (lsusb =~ /12d1:14ac/) ? ',15' : ''
          @serial_eats_sms = true
        when /airtel-modem/
          log_msg :SerialModem, 'Found 3G-modem with ttyUSB0-ttyUSB4'
          @serial_tty_error = '/dev/ttyUSB5'
          @serial_tty = '/dev/ttyUSB4'
          @ussd_add = ''
        else
          #puts caller.join("\n")
          @serial_tty = @serial_tty_error = nil
      end
      dputs(2){"serial_tty is #{@serial_tty.inspect} and exists " +
                              "#{File.exists?(@serial_tty.to_s)}"}
      if @serial_tty_error && File.exists?(@serial_tty_error)
        log_msg :SerialModem, 'resetting modem'
        reload_option
      end
    }
  end

  def start_serial_thread
    @serial_thread = Thread.new {
      #dputs_func
      dputs(2){'Thread started'}
      loop {
        begin
          dputs(5) { 'Reading out modem' }
          if read_reply.length == 0
            #@serial_sms.each { |id, sms|
            #  ddputs(3) { "Deleting sms #{sms.inspect} afterwards" }
            #  sms_delete(id)
            #}
          end

          dputs(4) { (Time.now - @serial_ussd_last).to_s }
          if (Time.now - @serial_ussd_last > @serial_ussd_timeout) &&
              (@serial_ussd.length > 0)
            log_msg :SerialModem, "Re-sending #{@serial_ussd.first}"
            ussd_send_now
          end

          sms_scan

          sleep 0.5
        rescue IOError
          log_msg :SerialModem, 'IOError - killing modem'
          kill
          return
        rescue Exception => e
          dputs(0) { "#{e.inspect}" }
          dputs(0) { "#{e.to_s}" }
          e.backtrace.each { |l| dputs(0) { l } }
        end
        dputs(5) { 'Finished' }
      }
      dputs(1) { 'Finished thread' }
    }
  end

  def reload_option
    @serial_sp and @serial_sp.close
    @serial_sp = nil
    dputs(1) { 'Trying to reload modem-driver - killing and reloading' }
    %w( chat ppp).each { |pro|
      System.run_str("killall -9 #{pro}")
    }
    %w(rmmod modprobe).each { |cmd|
      System.run_str("#{cmd} option")
    }
  end

  def kill
    #dputs_func
    if @serial_thread
      if @serial_thread.alive?
        dputs(3) { 'Killing thread' }
        @serial_thread.kill
        dputs(3) { 'Joining thread' }
        @serial_thread.join
        dputs(3) { 'Thread joined' }
      end
    end
    @serial_sp and @serial_sp.close
    dputs(1) { 'SerialModem killed' }
    @serial_sp = nil
  end

  def attached?
    @serial_sp != nil
  end

end
