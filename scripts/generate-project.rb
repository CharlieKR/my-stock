require 'xcodeproj'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'MyStock.xcodeproj'))
target = project.new_target(:application, 'MyStock', :ios, '26.0')
target.build_configurations.each do |config|
  settings = config.build_settings
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.charlie.mystock'
  settings['PRODUCT_NAME'] = 'My Stock'
  settings['SWIFT_VERSION'] = '6.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['INFOPLIST_KEY_CFBundleDisplayName'] = 'My Stock'
  settings['INFOPLIST_KEY_MyStockAPIURL'] = '$(MY_STOCK_API_URL)'
  settings['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  settings['INFOPLIST_KEY_UIApplicationSceneManifest_Generation'] = 'YES'
  settings['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
  settings['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
  settings['INFOPLIST_KEY_ITSAppUsesNonExemptEncryption'] = 'NO'
  settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  settings['CURRENT_PROJECT_VERSION'] = '1'
  settings['MARKETING_VERSION'] = '1.0.0'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['SWIFT_STRICT_CONCURRENCY'] = 'complete'
  settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG' if config.name == 'Debug'
end
group = project.main_group.new_group('MyStock', 'MyStock')
Dir.glob(File.join(root, 'MyStock', '**', '*.swift')).sort.each do |file|
  ref = group.new_file(file.delete_prefix(File.join(root, 'MyStock') + '/'))
  target.source_build_phase.add_file_reference(ref)
end
ref = group.new_file('Resources/Assets.xcassets')
target.resources_build_phase.add_file_reference(ref)
ui_tests = project.new_target(:ui_test_bundle, 'MyStockUITests', :ios, '26.0')
ui_tests.add_dependency(target)
ui_tests.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.charlie.mystock.uitests'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['TEST_TARGET_NAME'] = 'MyStock'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
end
test_group = project.main_group.new_group('MyStockUITests', 'MyStockUITests')
Dir.glob(File.join(root, 'MyStockUITests', '*.swift')).each do |file|
  ui_tests.source_build_phase.add_file_reference(test_group.new_file(File.basename(file)))
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.add_test_target(ui_tests)
scheme.save_as(project.path, 'MyStock', true)
puts 'Generated MyStock.xcodeproj'
