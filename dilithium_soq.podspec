Pod::Spec.new do |s|
  s.name             = 'dilithium_soq'
  s.version          = '1.0.0'
  s.summary          = 'Soqucoin FIPS 204 ML-DSA-44 Dilithium native library'
  s.description      = 'Native C implementation of FIPS 204 ML-DSA-44 (Dilithium Level 2) ' \
                        'for the SoquShield wallet. Uses the exact same source code as the ' \
                        'Soqucoin node to ensure byte-for-byte cryptographic compatibility.'
  s.homepage         = 'https://soqu.org'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Soqucoin Labs' => 'dev@soqu.org' }
  s.source           = { :path => '.' }

  # 15.0, matching ios/Podfile and the Runner project. Xcode 15+ refuses to
  # build a simulator slice below 15.0 at all, so a pod left at 13.0 fails the
  # whole build on a current toolchain — not just a warning.
  s.ios.deployment_target = '15.0'
  s.static_framework = true

  s.source_files = 'native/dilithium/**/*.{c,h}'
  s.public_header_files = 'native/dilithium/dilithium_ffi.h'

  s.compiler_flags = '-DDILITHIUM_MODE=2'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/native/dilithium"',
  }
end
