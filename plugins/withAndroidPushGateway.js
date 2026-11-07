const { AndroidConfig, withAndroidManifest } = require('expo/config-plugins')

// Only native build metadata supplies the public Cloud project NUMBER. Not an API key or a
// Firebase project ID; no page/Expo extra field may choose the Integrity verification project.
module.exports = (config, { projectNumber }) => withAndroidManifest(config, c => {
  if (!/^[1-9][0-9]{0,14}$/.test(projectNumber)) throw new Error('Invalid Play Integrity project number')
  const app = AndroidConfig.Manifest.getMainApplicationOrThrow(c.modResults)
  const metadata = app['meta-data'] ??= []
  const name = 'family.kinwall.PLAY_INTEGRITY_PROJECT_NUMBER'
  app['meta-data'] = metadata.filter(item => item.$['android:name'] !== name)
  // Prefix avoids AAPT treating the project number as a 32-bit integer resource.
  app['meta-data'].push({ $: { 'android:name': name, 'android:value': `project:${projectNumber}` } })
  return c
})
