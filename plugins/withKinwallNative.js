// iOS native targets, on top of @bacons/apple-targets (which turns targets/* into the widget,
// Watch, complication and share targets): links the KinwallKit Swift package to every target, and
// compiles native/ios (Siri App Intents) into the app itself, where AppShortcutsProvider has to live
// (and ShareReader.swift into the share extension too).
const { withXcodeProjectBeta } = require('@bacons/apple-targets/build/with-bacons-xcode')
const withTargets = require('@bacons/apple-targets/app.plugin')
const { PBXBuildFile, PBXFileReference, PBXNativeTarget, XCLocalSwiftPackageReference, XCSwiftPackageProductDependency } = require('@bacons/xcode')
const { AndroidConfig, withAndroidManifest, withAppDelegate, withDangerousMod, withEntitlementsPlist, withInfoPlist, withMainActivity, withXcodeProject } = require('expo/config-plugins')
const fs = require('fs')
const path = require('path')

// A project path with a space in it: the template's bundling phase runs an unquoted backtick
// path, and expo-constants' script phase expands $PODS_TARGET_SRCROOT unquoted inside `bash -c`.
const withSpacesInPath = (config) => {
  config = withXcodeProject(config, (config) => {
    const phases = config.modResults.hash.project.objects.PBXShellScriptBuildPhase
    for (const phase of Object.values(phases)) {
      if (typeof phase !== 'object' || !phase.shellScript) continue
      phase.shellScript = phase.shellScript.replace(/`(\\"\$NODE_BINARY\\" --print [^`]*)`/, '\\"$($1)\\"')
    }
    return config
  })
  return withDangerousMod(config, ['ios', (config) => {
    const podfile = path.join(config.modRequest.platformProjectRoot, 'Podfile')
    const fix = `
    installer.pods_project.targets.each do |t|
      t.shell_script_build_phases.each { |p| p.shell_script = p.shell_script.gsub('$PODS_TARGET_SRCROOT/../scripts/get-app-config-ios.sh', '\\"$PODS_TARGET_SRCROOT/../scripts/get-app-config-ios.sh\\"') }
    end
`
    fs.writeFileSync(podfile, fs.readFileSync(podfile, 'utf8').replace('post_install do |installer|\n', `post_install do |installer|${fix}`))
    return config
  }])
}

const withKinwallKit = (config) =>
  withXcodeProjectBeta(config, (config) => {
    const project = config.modResults
    const root = project.rootObject
    const pkg = XCLocalSwiftPackageReference.create(project, { relativePath: '../KinwallKit' })
    root.props.packageReferences = [...(root.props.packageReferences ?? []), pkg]
    for (const target of root.props.targets) {
      if (!PBXNativeTarget.is(target)) continue
      const dep = XCSwiftPackageProductDependency.create(project, { package: pkg, productName: 'KinwallKit' })
      target.props.packageProductDependencies = [...(target.props.packageProductDependencies ?? []), dep]
      target.getFrameworksBuildPhase().props.files.push(PBXBuildFile.create(project, { productRef: dep }))
    }
    // One version for the app and every extension (App Store Connect wants them equal); the
    // Info.plists read these, so `CURRENT_PROJECT_VERSION=…` on the xcodebuild line sets them all.
    for (const target of root.props.targets) {
      for (const c of target.props.buildConfigurationList.props.buildConfigurations) {
        c.props.buildSettings.MARKETING_VERSION = config.version
        c.props.buildSettings.CURRENT_PROJECT_VERSION = config.ios?.buildNumber ?? '1'
      }
    }
    const app = root.getMainAppTarget('ios')
    const dir = path.join(config.modRequest.projectRoot, 'native/ios')
    const addFile = (target, file) => {
      const ref = PBXFileReference.create(project, { path: `../${file}`, sourceTree: 'SOURCE_ROOT', lastKnownFileType: 'sourcecode.swift' })
      root.props.mainGroup.props.children.push(ref)
      target.getSourcesBuildPhase().ensureFile({ fileRef: ref })
    }
    for (const file of fs.readdirSync(dir).filter((f) => f.endsWith('.swift'))) addFile(app, `native/ios/${file}`)
    // iPhone Settings → Kinwall: how to delete the family's account (native/ios/Settings.bundle).
    const settings = PBXFileReference.create(project, { path: '../native/ios/Settings.bundle', sourceTree: 'SOURCE_ROOT', lastKnownFileType: 'wrapper.plug-in' })
    root.props.mainGroup.props.children.push(settings)
    app.getResourcesBuildPhase().ensureFile({ fileRef: settings })
    // The Live Activities: the widget extension draws what the app's native module starts, so it
    // compiles the module's attributes too (ActivityKit matches them by name), and Got it's intent.
    const widgets = root.props.targets.find((t) => PBXNativeTarget.is(t) && t.props.productName === 'KinwallWidgets')
    if (!widgets) throw new Error('withKinwallKit: no KinwallWidgets target')
    // The Controls (targets/widgets/Controls.swift) run the open-the-app intents, which iOS runs in the app.
    for (const file of ['modules/kinwall-native/ios/KinwallActivityAttributes.swift', 'native/ios/LiveActivityIntents.swift', 'native/ios/OpenIntents.swift']) addFile(widgets, file)
    // A shared photo's text (native/ios/ShareReader.swift): the share sheet reads it too.
    const share = root.props.targets.find((t) => PBXNativeTarget.is(t) && t.props.productName === 'KinwallShare')
    if (!share) throw new Error('withKinwallKit: no KinwallShare target')
    addFile(share, 'native/ios/ShareReader.swift')
    return config
  })

// The app's own Info.plist follows the build setting too; and no push entitlement (expo-notifications
// adds one): reminders are local, and a Personal Team can't sign push. KINWALL_PUSH=1 at prebuild
// (a paid team, docs/PLAN.md) keeps it for the Live Activities' Apple push, and KinwallPush tells
// the app to ask for their tokens.
const PUSH = process.env.KINWALL_PUSH === '1'
// Time Sensitive reminders (leave-by and medicine break through a Focus) need their entitlement,
// which the Personal Team's profile doesn't carry: a paid team (KINWALL_PUSH=1), or
// KINWALL_TIME_SENSITIVE=1 to try it on another, adds it and sets KinwallTimeSensitive, which
// modules/kinwall-native/ios/Reminders.swift reads. Without it they're ordinary notifications.
const TIME_SENSITIVE = PUSH || process.env.KINWALL_TIME_SENSITIVE === '1'
const withLocalOnly = (config) => {
  config = withInfoPlist(config, (c) => { c.modResults.CFBundleVersion = '$(CURRENT_PROJECT_VERSION)'; c.modResults.KinwallPush = PUSH; c.modResults.KinwallTimeSensitive = TIME_SENSITIVE; return c })
  return withEntitlementsPlist(config, (c) => {
    if (!PUSH) delete c.modResults['aps-environment']
    if (TIME_SENSITIVE) c.modResults['com.apple.developer.usernotifications.time-sensitive'] = true
    return c
  })
}

// iOS 27 kills apps built with its SDK at launch unless they use the scene life cycle (the
// simulator only warns). Expo ships the scene delegate; the prebuild template's AppDelegate doesn't
// use it yet, so hand window creation to it: declare the scene, and stop starting React Native in
// the app delegate. Drop this once the template does it.
const withSceneLifecycle = (config) => {
  config = withInfoPlist(config, (c) => {
    c.modResults.UIApplicationSceneManifest = {
      UIApplicationSupportsMultipleScenes: false,
      UISceneConfigurations: {
        UIWindowSceneSessionRoleApplication: [
          { UISceneConfigurationName: 'Default Configuration', UISceneDelegateClassName: 'EXExpoAppSceneDelegate' },
        ],
      },
    }
    return c
  })
  return withAppDelegate(config, (c) => {
    let src = c.modResults.contents
    if (!src.includes('ExpoReactNativeFactoryProvider')) {
      src = src.replace('class AppDelegate: ExpoAppDelegate {', 'class AppDelegate: ExpoAppDelegate, ExpoReactNativeFactoryProvider {')
      src = src.replace(/\n#if os\(iOS\) \|\| os\(tvOS\)\n\s*window = UIWindow\(frame: UIScreen\.main\.bounds\)\n\s*factory\.startReactNative\([\s\S]*?\)\n#endif\n/, '\n')
      if (src.includes('startReactNative')) throw new Error('withSceneLifecycle: the AppDelegate template changed; update the patch')
    }
    c.modResults.contents = src
    return c
  })
}

// Our native code's hooks in the generated AppDelegate (native/ios/AppHooks.swift): Siri's
// parameter lists at launch, and a tapped Spotlight result.
const withAppHooks = (config) =>
  withAppDelegate(config, (c) => {
    let src = c.modResults.contents
    if (src.includes('AppHooks.')) return c
    const launch = /(\n\s*)return super\.application\(application, didFinishLaunchingWithOptions: launchOptions\)/
    const resume = /(\n\s*)let result = RCTLinkingManager\.application\(application, continue: userActivity, restorationHandler: restorationHandler\)/
    if (!launch.test(src) || !resume.test(src)) throw new Error('withAppHooks: the AppDelegate template changed; update the patch')
    src = src.replace(launch, '$1AppHooks.launched()$&')
    src = src.replace(resume, '$1if AppHooks.open(userActivity) { return true }$&')
    c.modResults.contents = src
    return c
  })

// Android's share sheet: "Kinwall" takes links, text and photos in its own small sheet
// (modules/kinwall-native ShareActivity.kt, which declares those filters), and shared contacts
// (vCards) here, on the main activity, before React Native reads the intent: a contact's vCard goes
// to the cache for KinwallNative.takeSharedContacts, and ?to=contacts/import opens the page's review
// (src/WebShell.tsx). A vCard shared as plain text reaches ShareActivity, which hands it on here.
// The iOS equivalent is targets/share.
const OVERRIDE_MIN_SDK = ['com.google.mlkit.genai.prompt', 'com.google.mlkit.genai.common', 'com.google.mlkit.nl.entityextraction']
const VCARD_TYPES = ['text/x-vcard', 'text/vcard', 'text/directory']
const SHARE_KOTLIN = String.raw`
  private fun shareToApp(intent: Intent?) {
    if (intent != null) shareContacts(intent)
  }

  // Shared contacts (ACTION_SEND or ACTION_SEND_MULTIPLE of a vCard, or a vCard shared as plain
  // text, whose URL: line would otherwise open the recipe import): their text goes to the cache
  // (KinwallNativeModule's takeSharedContacts) and the intent becomes ?to=contacts/import; n= makes
  // each share a new link. A contact that can't be read still opens Contacts.
  private fun shareContacts(intent: Intent): Boolean {
    if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) return false
    val vcardText = intent.type?.lowercase() == "text/plain" && intent.getStringExtra(Intent.EXTRA_TEXT)?.contains("BEGIN:VCARD", ignoreCase = true) == true
    if (!vcardText && intent.type?.lowercase() !in listOf("text/x-vcard", "text/vcard", "text/directory")) return false
    val uris = if (intent.action == Intent.ACTION_SEND_MULTIPLE) IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
      else listOfNotNull(IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java))
    val file = File(cacheDir, "shared-contacts.vcf")
    try {
      // ponytail: read in full on the main thread; fine for the few contacts people share at once.
      val text = uris.joinToString("\r\n") { uri -> contentResolver.openInputStream(uri)?.use { String(it.readBytes(), Charsets.UTF_8) } ?: "" }
        .ifBlank { intent.getStringExtra(Intent.EXTRA_TEXT).orEmpty() }
      if (text.contains("BEGIN:VCARD", ignoreCase = true)) file.writeText(text) else file.delete()
    } catch (e: Exception) {
      file.delete()
    }
    intent.action = Intent.ACTION_VIEW
    intent.data = Uri.parse("family.kinwall.app:/open?to=contacts%2Fimport&n=" + System.currentTimeMillis())
    return true
  }

  override fun onNewIntent(intent: Intent) {
    shareToApp(intent)
    super.onNewIntent(intent)
  }
`
const withShareIntent = (config) => {
  config = withAndroidManifest(config, (c) => {
    const activity = AndroidConfig.Manifest.getMainActivityOrThrow(c.modResults)
    const filters = (activity['intent-filter'] ??= [])
    const has = (action, type) => filters.some((f) => f.action?.some((a) => a.$['android:name'] === action) && f.data?.some((d) => d.$['android:mimeType'] === type))
    const add = (action, types) => {
      if (types.every((t) => has(action, t))) return
      filters.push({ action: [{ $: { 'android:name': action } }], category: [{ $: { 'android:name': 'android.intent.category.DEFAULT' } }], data: types.map((t) => ({ $: { 'android:mimeType': t } })) })
    }
    add('android.intent.action.SEND', VCARD_TYPES)
    add('android.intent.action.SEND_MULTIPLE', VCARD_TYPES)
    const app = c.modResults.manifest.application[0]
    // Text recognition's Play services model downloads with the app, next to expo-camera's scanner UI.
    const meta = (app['meta-data'] ??= [])
    const deps = meta.find((m) => m.$['android:name'] === 'com.google.mlkit.vision.DEPENDENCIES') ?? meta[meta.push({ $: { 'android:name': 'com.google.mlkit.vision.DEPENDENCIES' } }) - 1]
    Object.assign(deps.$, { 'android:value': 'barcode_ui,ocr', 'tools:replace': 'android:value' })
    // Entity extraction and Gemini Nano say Android 8; ShareReader.kt skips them on Android 7.
    c.modResults.manifest['uses-sdk'] = [{ $: { 'tools:overrideLibrary': OVERRIDE_MIN_SDK.join(',') } }]
    return c
  })
  return withMainActivity(config, (c) => {
    let src = c.modResults.contents
    if (src.includes('shareToApp')) return c
    if (c.modResults.language !== 'kt' || !src.includes('super.onCreate(')) throw new Error('withShareIntent: the MainActivity template changed; update the patch')
    src = src.replace(/\nimport android\.os\.Bundle\n/, '\nimport android.content.Intent\nimport android.net.Uri\nimport android.os.Bundle\nimport androidx.core.content.IntentCompat\nimport java.io.File\n')
    src = src.replace(/(\n\s*)super\.onCreate\(/, '$1shareToApp(intent)$1super.onCreate(')
    src = src.replace(/\n}\s*$/, `\n${SHARE_KOTLIN}}\n`)
    c.modResults.contents = src
    return c
  })
}

// Exact alarms for the leave-by, medicine and cooking-timer alarms (Countdowns.kt): USE_EXACT_ALARM
// is granted at install on Android 13 and later (Play allows it for calendar and reminder apps, with
// a declaration: docs/PUBLISHING.md); SCHEDULE_EXACT_ALARM covers Android 12 and 12L, where it's
// granted by default too, and is capped there so Android 13+ never shows its settings toggle.
const withExactAlarms = (config) =>
  withAndroidManifest(config, (c) => {
    const perms = (c.modResults.manifest['uses-permission'] ??= [])
    const perm = (name) => perms.find((p) => p.$['android:name'] === name) ?? perms[perms.push({ $: { 'android:name': name } }) - 1]
    perm('android.permission.USE_EXACT_ALARM')
    Object.assign(perm('android.permission.SCHEDULE_EXACT_ALARM').$, { 'android:maxSdkVersion': '32', 'tools:replace': 'android:maxSdkVersion' })
    return c
  })

// The launcher's shortcuts (Add to Groceries, Start shopping, My chores, Night screen), in
// modules/kinwall-native/android res/xml/kinwall_shortcuts.xml, on the main activity.
const withShortcuts = (config) =>
  withAndroidManifest(config, (c) => {
    const activity = AndroidConfig.Manifest.getMainActivityOrThrow(c.modResults)
    const meta = (activity['meta-data'] ??= [])
    if (!meta.some((m) => m.$['android:name'] === 'android.app.shortcuts')) meta.push({ $: { 'android:name': 'android.app.shortcuts', 'android:resource': '@xml/kinwall_shortcuts' } })
    return c
  })

// Mods run newest-first, so register ours before apple-targets' and it runs once the targets exist.
module.exports = (config) => withTargets(withKinwallKit(withLocalOnly(withAppHooks(withSceneLifecycle(withSpacesInPath(withShortcuts(withExactAlarms(withShareIntent(config)))))))), {})
