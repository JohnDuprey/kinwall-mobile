/** Re-lock selected entertainment apps at the grant's cutoff, even while Kinwall is closed. */
module.exports = {
  type: 'device-activity-monitor',
  name: 'KinwallRoutineMonitor',
  displayName: 'Kinwall routine',
  bundleIdentifier: '.routine-monitor',
  deploymentTarget: '17.0',
  frameworks: ['DeviceActivity', 'FamilyControls', 'ManagedSettings'],
  entitlements: {
    'com.apple.developer.family-controls': true,
    'com.apple.security.application-groups': ['group.family.kinwall.routine'],
  },
}
