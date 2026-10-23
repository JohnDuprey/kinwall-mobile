/** @type {import('@bacons/apple-targets/app.plugin').Config} */
module.exports = {
  type: 'watch-widget',
  name: 'KinwallWatchWidgets',
  displayName: 'Kinwall',
  bundleIdentifier: '.watchkitapp.complications',
  deploymentTarget: '10.0',
  frameworks: ['SwiftUI', 'WidgetKit'],
  // These extensions use the shared Keychain, not Routine Mode's App Group.
  entitlements: { 'com.apple.security.application-groups': [], 'keychain-access-groups': ['$(AppIdentifierPrefix)family.kinwall.shared'] },
}
