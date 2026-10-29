Pod::Spec.new do |s|
  s.name = 'SimlaPushNotificationExtension'
  s.version = '0.1.0'
  s.summary = 'Notification service extension support for the Simla iOS SDK.'
  s.homepage = 'https://github.com/simla-tech/MobileSdkIOS'
  s.license = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author = 'Simla'
  s.source = { :git => 'https://github.com/simla-tech/MobileSdkIOS.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.swift_version = '5.0'
  s.module_name = 'PushNotificationExtension'
  s.source_files = 'Sources/PushNotificationExtension/**/*.swift'
  # Keep Swift package access shared between SDK modules, as in SPM.
  s.pod_target_xcconfig = {
    'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name ConsultantSdk',
    'PODS_DEVELOPMENT_LANGUAGE' => 'ru',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES'
  }
  s.resource_bundles = { 'SimlaPushNotificationExtension' => ['Sources/PushNotificationExtension/Resources/**/*'] }
  s.dependency 'SimlaSDKConfiguration', s.version.to_s
  s.dependency 'SimlaSQLiteStorage', s.version.to_s
end
