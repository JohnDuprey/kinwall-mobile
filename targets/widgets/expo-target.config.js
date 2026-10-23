/** @type {import('@bacons/apple-targets/app.plugin').Config} */
module.exports = {
  type: 'widget',
  name: 'KinwallWidgets',
  displayName: 'Kinwall',
  bundleIdentifier: '.widgets',
  deploymentTarget: '17.0',
  frameworks: ['SwiftUI', 'WidgetKit', 'AppIntents'],
  // These extensions use the shared Keychain, not Routine Mode's App Group.
  entitlements: { 'com.apple.security.application-groups': [], 'keychain-access-groups': ['$(AppIdentifierPrefix)family.kinwall.shared'] },
}
