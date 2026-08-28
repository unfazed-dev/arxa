#
# ffi plugin: no Swift/ObjC sources — the pod exists to run cargokit's
# build_pod.sh and force-load the resulting static library.
#
Pod::Spec.new do |s|
  s.name             = 'arxa_kit_studio_transport'
  s.version          = '0.1.0'
  s.summary          = 'iroh-backed pairing transport for arxa studio (Rust core).'
  s.description      = 'QR pairing, AUTH handshake, loopback HTTP proxy, push relay over iroh QUIC.'
  s.homepage         = 'https://arxa.dev'
  s.license          = { :type => 'Proprietary', :text => 'Copyright Arxa Digital Solutions' }
  s.author           = { 'Arxa Digital Solutions' => 'evan.dev.pierrelouis@gmail.com' }

  s.source           = { :path => '.' }
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust arxa_studio_transport',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ['${BUILT_PRODUCTS_DIR}/libarxa_studio_transport.a'],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'DEAD_CODE_STRIPPING' => 'YES',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libarxa_studio_transport.a',
  }
end
