require 'fileutils'
require 'pathname'
require 'xcodeproj'

sdk_path = Pathname.new(ARGV.fetch(0)).expand_path
build_path = Pathname.new(ARGV.fetch(1)).expand_path
FileUtils.mkdir_p(build_path)
project = Xcodeproj::Project.new(build_path.join('PodBuild.xcodeproj'))
app = project.new_target(:application, 'PodBuild', :ios, '15.0')
notification_extension = project.new_target(:app_extension, 'NotificationService', :ios, '15.0')

[app, notification_extension].each do |target|
  target.build_configurations.each do |config|
    config.build_settings.merge!(
      'SWIFT_VERSION' => '5.0',
      'GENERATE_INFOPLIST_FILE' => 'YES',
      'CURRENT_PROJECT_VERSION' => '1',
      'MARKETING_VERSION' => '1.0',
      'CODE_SIGNING_ALLOWED' => 'NO',
      'PRODUCT_BUNDLE_IDENTIFIER' => "com.simla.PodBuild#{target == app ? '' : '.NotificationService'}"
    )
  end
end

app.build_configurations.each do |config|
  config.build_settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
end
notification_extension.build_configurations.each do |config|
  config.build_settings['INFOPLIST_FILE'] = 'NotificationInfo.plist'
  config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
end
Xcodeproj::Plist.write_to_path(
  { 'NSExtension' => {
      'NSExtensionPointIdentifier' => 'com.apple.usernotifications.service',
      'NSExtensionPrincipalClass' => '$(PRODUCT_MODULE_NAME).NotificationService'
  } }, build_path.join('NotificationInfo.plist')
)

app.add_dependency(notification_extension)
embed = app.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
embed.add_file_reference(notification_extension.product_reference)

File.write(build_path.join('App.swift'), <<~SWIFT)
  import UIKit
  import Core
  import OnlineConsultant
  import Tracker
  import Recommendations
  import PushService
  import PushNotificationExtension

  @main final class AppDelegate: UIResponder, UIApplicationDelegate {
      var window: UIWindow?
  }
SWIFT
File.write(build_path.join('NotificationService.swift'), <<~SWIFT)
  import UserNotifications
  import PushNotificationExtension

  final class NotificationService: UNNotificationServiceExtension {
      private let handler = PushNotificationHandler(siteToken: "ci-build")
  }
SWIFT
app.add_file_references([project.main_group.new_file('App.swift')])
notification_extension.add_file_references([project.main_group.new_file('NotificationService.swift')])
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'PodBuild', true)

File.write(build_path.join('Podfile'), <<~PODS)
  source 'https://cdn.cocoapods.org/'
  platform :ios, '15.0'
  use_frameworks! :linkage => :static

  sdk_path = #{sdk_path.to_s.dump}
  target 'PodBuild' do
    %w[
      SimlaCore SimlaOnlineConsultant SimlaTracker SimlaRecommendations
      SimlaPushService SimlaPushNotificationExtension SimlaSDKConfiguration SimlaSQLiteStorage
    ].each do |name|
      pod name, :path => sdk_path
    end
  end

  target 'NotificationService' do
    pod 'SimlaSDKConfiguration', :path => sdk_path
    pod 'SimlaSQLiteStorage', :path => sdk_path
    pod 'SimlaPushNotificationExtension', :path => sdk_path
  end
PODS
puts "CocoaPods build project: #{build_path}"
