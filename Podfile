# Uncomment the next line to define a global platform for your project
platform :ios, '17.0'
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings.delete 'IPHONEOS_DEPLOYMENT_TARGET'
    end
  end
end

target 'ARTest' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for ARTest
  pod 'MessagePacker'

  target 'ARTestTests' do
    inherit! :search_paths
    # Pods for testing
  end

  target 'ARTestUITests' do
    # Pods for testing
  end
end
