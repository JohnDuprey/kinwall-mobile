Pod::Spec.new do |s|
  s.name           = 'KinwallNative'
  s.version        = '0.1.0'
  s.summary        = 'Kinwall: WidgetKit reloads, Live Activities, Spotlight and the Apple Watch link'
  s.author         = 'Kinwall'
  s.homepage       = 'https://github.com/JohnDuprey/kinwall-mobile'
  s.license        = 'AGPL-3.0'
  s.platforms      = { :ios => '17.0' }
  s.source         = { git: '' }
  s.static_framework = true
  s.dependency 'ExpoModulesCore'
  s.frameworks = 'WidgetKit', 'WatchConnectivity', 'ActivityKit', 'CoreSpotlight', 'DeviceCheck', 'CryptoKit'
  s.weak_frameworks = 'AlarmKit' # iOS 26 and later; the deployment target is 17
  s.source_files = '**/*.swift'
end
