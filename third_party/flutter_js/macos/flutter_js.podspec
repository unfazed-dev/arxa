#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_js.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_js'
  s.version          = '0.0.1'
  s.summary          = 'A new flutter plugin project.'
  s.description      = <<-DESC
A new flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  # Points at the Swift Package sources so CocoaPods and Swift Package Manager
  # compile the SAME files. Upstream 0.8.7 read 'Classes/**/*'; the sources moved
  # to flutter_js/Sources/flutter_js/ for SPM (Flutter 3.44 defaults SPM on, and
  # this plugin has not migrated upstream). Nothing else in this podspec changed.
  s.source_files     = 'flutter_js/Sources/flutter_js/**/*.swift'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
