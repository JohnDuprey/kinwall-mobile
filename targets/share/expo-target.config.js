/** @type {import('@bacons/apple-targets/app.plugin').Config} */
// The share sheet's "Kinwall": adds a shared link, place, photo or text (ShareViewController.swift, and
// native/ios/ShareReader.swift through plugins/withKinwallNative.js) or imports a contact (ContactImport.swift)
// on the spot, signed in with what the app keeps in the shared Keychain group.
module.exports = {
  type: 'share',
  name: 'KinwallShare',
  displayName: 'Kinwall',
  bundleIdentifier: '.share',
  deploymentTarget: '17.0',
  frameworks: ['UIKit', 'UniformTypeIdentifiers', 'Vision'],
  entitlements: { 'keychain-access-groups': ['$(AppIdentifierPrefix)family.kinwall.shared'] },
}
