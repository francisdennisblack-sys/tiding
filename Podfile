platform :ios, '16.0'

use_frameworks! :linkage => :static

target 'Spot' do
  # Firebase (moved from SPM to CocoaPods to avoid FBLPromises conflicts with ML Kit)
  pod 'FirebaseAuth', '12.18.0'
  pod 'FirebaseCore', '12.18.0'
  pod 'FirebaseDatabase', '12.18.0'
  pod 'FirebaseFirestore', '12.18.0'
  pod 'FirebaseFunctions', '12.18.0'
  pod 'FirebaseStorage', '12.18.0'
  pod 'FirebaseAppCheck', '12.18.0'

  # ML Kit Text Recognition for ID scanning.
  pod 'GoogleMLKit/TextRecognition', '7.0.0'

  target 'SpotTests' do
    inherit! :search_paths
  end

  target 'SpotUITests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
      config.build_settings['SWIFT_EMIT_APP_INTENTS_METADATA'] = 'NO'
      config.build_settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf'
      config.build_settings['COMPILER_INDEX_STORE_ENABLE'] = 'NO'
      config.build_settings['CLANG_ENABLE_MODULE_DEBUGGING'] = 'NO'
      config.build_settings['SWIFT_COMPILATION_MODE'] = 'singlefile'
      config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone'
    end
  end
end






