# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = 'SerialModem'
  spec.version       = '0.2.1'
  spec.authors       = ['Linus Gasser']
  spec.email         = ['ineiti@linusetviviane.ch']
  spec.summary       = %q{Interface to serial-usb-modems}
  spec.description   = %q{This can interface a lot of different usb-modems}
  spec.homepage      = 'https://github.com/ineiti/SerialModem'
  spec.license       = 'GPLv3'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_runtime_dependency 'serialport', '1.3.1'
end
