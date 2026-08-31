#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_lite_camera.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_lite_camera'
  s.version          = '0.2.1'
  s.summary          = 'A lightweight Flutter camera plugin.'
  s.description      = <<-DESC
A lightweight Flutter camera plugin that renders previews natively through
Flutter textures and captures RGB frames on demand for image processing.
                       DESC
  s.homepage         = 'https://github.com/yushulx/flutter_lite_camera'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'yushulx' => 'yushulx@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files = 'flutter_lite_camera/Sources/flutter_lite_camera/**/*.swift'

  s.resource_bundles = {'flutter_lite_camera_privacy' => ['flutter_lite_camera/Sources/flutter_lite_camera/PrivacyInfo.xcprivacy']}
  s.frameworks = ['AVFoundation', 'CoreMedia', 'CoreVideo']
  s.dependency 'Flutter'

  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
