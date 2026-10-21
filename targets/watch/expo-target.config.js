/** @type {import('@bacons/apple-targets/app.plugin').Config} */
module.exports = {
  type: 'watch',
  name: 'KinwallWatch',
  displayName: 'Kinwall',
  // apple-targets also uses this to select AppIcon for asset compilation.
  icon: '../../assets/icon.png',
  bundleIdentifier: '.watchkitapp',
  deploymentTarget: '10.0',
  frameworks: ['SwiftUI', 'WatchConnectivity', 'WidgetKit'],
  entitlements: { 'keychain-access-groups': ['$(AppIdentifierPrefix)family.kinwall.shared'] },
}
