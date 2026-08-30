#
# ffi plugin: no Swift/ObjC sources — the pod exists to run cargokit's
# build_pod.sh and force-load the resulting static library.
# iOS caveat: see README "iOS: static lib + symbol stripping".
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
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
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
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'DEAD_CODE_STRIPPING' => 'YES',
    # Static lib caveat: the linker sees no direct symbol references from the
    # app, so force-load keeps the FRB entry points alive.
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libarxa_studio_transport.a',
  }
  # pod_target_xcconfig only affects the pod target, and a static-lib pod has
  # no link step of its own — the flag above never reached the app link, so
  # the Rust archive was silently dropped (dlopen then failed at runtime).
  # user_target_xcconfig propagates to the app target's final link.
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/arxa_kit_studio_transport/libarxa_studio_transport.a',
    # Release/profile links run -Xlinker -dead_strip. Nothing in the app
    # references the FRB entry points statically (they are dlsym'd at
    # runtime), so dead stripping deleted the entire force-loaded Rust
    # core from device builds: RustLib.init then failed and the mobile
    # pairing flow spun forever (2026-08-30, verified via nm/strings on
    # the linked Runner). Keep the archive's bytes alive.
    'DEAD_CODE_STRIPPING' => 'NO',
  }
end
