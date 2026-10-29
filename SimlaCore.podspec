Pod::Spec.new do |s|
  s.name = 'SimlaCore'
  s.version = '0.1.0'
  s.summary = 'Shared configuration, sessions and networking for the Simla iOS SDK.'
  s.homepage = 'https://github.com/simla-tech/MobileSdkIosTest'
  s.license = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author = 'Simla'
  s.source = { :git => 'https://github.com/simla-tech/MobileSdkIosTest.git', :tag => s.version.to_s }
  s.ios.deployment_target = '15.0'
  s.swift_version = '5.0'
  s.module_name = 'Core'
  s.source_files = 'Sources/Core/**/*.swift'
  # Keep Swift package access shared between SDK modules, as in SPM.
  s.pod_target_xcconfig = {
    'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name ConsultantSdk',
    'PODS_DEVELOPMENT_LANGUAGE' => 'ru'
  }
  s.resource_bundles = { 'SimlaCore' => ['Sources/Core/Resources/**/*'] }
  s.frameworks = 'Security'
  s.dependency 'SimlaSDKConfiguration', s.version.to_s
end
