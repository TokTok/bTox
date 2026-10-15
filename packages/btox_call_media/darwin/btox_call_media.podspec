Pod::Spec.new do |s|
  s.name             = 'btox_call_media'
  s.version          = '0.1.0'
  s.summary          = 'Call audio and video for bTox.'
  s.homepage         = 'https://github.com/TokTok/btox'
  s.license          = { :type => 'GPL-3.0-or-later' }
  s.author           = { 'The TokTok team' => 'https://toktok.ltd' }
  s.source           = { :path => '.' }
  # The files here include the shared ones in ../src and ../third_party.
  s.source_files     = 'Classes/**/*'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '11.0'
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreAudio', 'CoreMedia', 'CoreVideo'
  s.ios.frameworks = 'UIKit'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'HAVE_CONFIG_H=1 MA_NO_DECODING=1 MA_NO_ENCODING=1 MA_NO_ENGINE=1 MA_NO_GENERATION=1 MA_NO_NODE_GRAPH=1 MA_NO_RESOURCE_MANAGER=1',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../src" "${PODS_TARGET_SRCROOT}/../src/speexdsp" "${PODS_TARGET_SRCROOT}/../third_party/miniaudio" "${PODS_TARGET_SRCROOT}/../third_party/speexdsp/include"',
  }
end
