# SerialModem

Simple interface for Serial Modems. Tested:
- Huawei E303 in serial mode

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'SerialModem'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install SerialModem

## Usage

### Simple

If everything is connected and the modem is recognized (/dev/ttyUSB* is
 available), then you can simply do:

```
require 'serialmodem'

SerialModem::setup_modem
return unless SerialModem.attached?

SerialModem::ussd_send('*100#')
SerialModem::sms_send('+23599999999', 'Hello from SerialModem')
```

### Ussd

Huawei-modems with Hilink don't support USSD, so you have to switch them
to serial-mode. Older modems (pre-2015) are handled with _HilinkModem_, newer versions
not yet. Once the modem is in serial-mode, you can send and receive USSD-codes.
It is even possible to use USSD-menus.

#### Sending

Supposing the modem is setup, you can do

```
SerialModem::send_ussd('*100#')
```

Or, if you need a menu where each step needs an answer, you can do

```
SerialModem::send_ussd('*800#', '1', '2', '1234')
```

Now each command waits for the last command to be completed.

#### Receiving

The received codes are stored in an array of hashes, where each hash has
three fields:

  - time: a string of "%H:%M"
  - code: the ussd-code as sent out by 'ussd_send'
  - result

There is a maximum of _SerialModem::serial_ussd_results_max_ messages
stored.

```
SerialModem::send_ussd('*128#')
sleep 10
result = SerialModem.serial_ussd_results.first.result
```

#### Asynchronous receiving

You can also define a listener in _SerialModem.serial_ussd_new_

### SMS

Similar to USSD, you can send and receive SMS. Due to some restrictions in
Huawei-modems, there is a thread that checks for new SMSs every 20s. Normally
modems should reply as soon as an SMS is received, but most of the Huawei-modems
tested delete SMS automatically when in this mode. If you prefer nonethelss to
rely on this mode, set _SerialModem.serial_sms_autoscan_ to 0.

#### Sending

If everything is recognized, simply do:

```
SerialModem.sms_send('+23599999999', 'Hello from SerialModem')
```

And the message should be sent.

#### Receiving

All SMS are put in a hash of arrays with the key of the hash being the message-id
 and the elements of the array as follows:

0: sms-flag
1: number of sender
2: unknown field
3: date and time of SMS
4: the message

#### Asynchronous receiving

You can also use the _SerialModem.serial_sms_new_ variable to set up an
automatic callback whenever a new SMS is received:

```

def treat_sms(list, id)
  p "Received SMS from #{list[id][1]}"
end

SerialModem.serial_sms_new.push(Proc.new { |list, id| treat_sms(list, id) })

# Wait for SMS
```

## Special

Some care has been taken that the serial modem is recognized and can be
functional again in case of error:

### detach and re-attach in case of power-failure

It can happen that the modem is in use and is reattached because of errors in the
power. In that case it is not attached anymore to '/dev/ttyUSB2', but to
'/dev/ttyUSB3'. With some luck, the _SerialModem.reload_option_ can help to
make things OK again.