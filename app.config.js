// app.json, plus the release build number: CI sets KINWALL_BUILD_NUMBER (major*10000 + minor*100 +
// patch, .github/workflows/build.yml) so every release's iOS buildNumber and Android versionCode
// go up with its version. Local builds keep app.json's.
// Supply an untracked Firebase client config only for builds that use native Android push.
module.exports = ({ config }) => {
  const build = process.env.KINWALL_BUILD_NUMBER
  const firebase = process.env.KINWALL_GOOGLE_SERVICES_FILE || config.android?.googleServicesFile
  return {
    ...config,
    ...(build ? { ios: { ...config.ios, buildNumber: build } } : {}),
    android: { ...config.android, ...(build ? { versionCode: Number(build) } : {}),
      ...(firebase ? { googleServicesFile: firebase } : {}) },
    extra: { ...config.extra, androidNativePush: !!firebase },
  }
}
