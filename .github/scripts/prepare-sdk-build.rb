require 'fileutils'
require 'optparse'
require 'pathname'
require 'xcodeproj'

options = { manager: 'pod' }
OptionParser.new do |parser|
  parser.on('--manager MANAGER', %w[pod spm]) { |value| options[:manager] = value }
  parser.on('--git URL') { |value| options[:git] = value }
  parser.on('--tag VERSION') { |value| options[:tag] = value }
end.parse!
abort 'Pass --git and --tag together.' if options.key?(:git) != options.key?(:tag)
if options[:manager] == 'spm' && !options.key?(:git)
  abort 'SPM integration builds require --git and --tag.'
end

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

if options[:manager] == 'spm'
  package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  package.repositoryURL = options.fetch(:git)
  package.requirement = { 'kind' => 'exactVersion', 'version' => options.fetch(:tag) }
  project.root_object.package_references << package
  {
    app => %w[Core OnlineConsultant Tracker Recommendations PushService PushNotificationExtension],
    notification_extension => %w[PushNotificationExtension]
  }.each do |target, products|
    products.each do |name|
      product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
      product.package = package
      product.product_name = name
      target.package_product_dependencies << product
      link = project.new(Xcodeproj::Project::Object::PBXBuildFile)
      link.product_ref = product
      target.frameworks_build_phase.files << link
    end
  end
end

project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'PodBuild', true)

if options[:manager] == 'pod'
  sdk_source = if options.key?(:git)
                 { git: options.fetch(:git), tag: options.fetch(:tag) }
               else
                 { path: sdk_path.to_s }
               end
  File.write(build_path.join('Podfile'), <<~PODS)
    source 'https://cdn.cocoapods.org/'
    platform :ios, '15.0'
    use_frameworks! :linkage => :static

    sdk_source = #{sdk_source.inspect}
    target 'PodBuild' do
      %w[
        SimlaCore SimlaOnlineConsultant SimlaTracker SimlaRecommendations
        SimlaPushService SimlaPushNotificationExtension SimlaSDKConfiguration SimlaSQLiteStorage
      ].each do |name|
        pod name, sdk_source
      end
    end

    target 'NotificationService' do
      pod 'SimlaSDKConfiguration', sdk_source
      pod 'SimlaSQLiteStorage', sdk_source
      pod 'SimlaPushNotificationExtension', sdk_source
    end
  PODS
end
puts "#{options[:manager]} integration build project: #{build_path}"
