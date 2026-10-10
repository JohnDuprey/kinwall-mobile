# Changelog

## [1.2.0](https://github.com/JohnDuprey/kinwall-mobile/compare/v1.1.0...v1.2.0) (2026-10-10)


### New

* **android:** send shares and photos to kinwall from the share sheet ([742f5c7](https://github.com/JohnDuprey/kinwall-mobile/commit/742f5c7ca92c789693c0d79c2479425819436780))
* **ios:** add dinner, reading, poll and event Siri actions ([d95200a](https://github.com/JohnDuprey/kinwall-mobile/commit/d95200a0a65a9c5def22a5c09709746ea21a5aa7))
* **ios:** send shares and photos to kinwall from the share sheet ([08d8a77](https://github.com/JohnDuprey/kinwall-mobile/commit/08d8a77d6e2e6812b23023a38850edcfd6ecb42e))
* **native:** show a cooking range's check on the lock screen and ring it ([2047f60](https://github.com/JohnDuprey/kinwall-mobile/commit/2047f60355576ce4bf9282664f49ea057301e89e))
* **share:** add a shared event to a calendar right from the share sheet ([4957d2e](https://github.com/JohnDuprey/kinwall-mobile/commit/4957d2eb0c55a68c5937431bf2e8ec417a704de4))
* **share:** add notes and default the calendar to the family's pick ([f4e7a86](https://github.com/JohnDuprey/kinwall-mobile/commit/f4e7a86533fe3c02539c1254d53faff9a0202f0f))
* **share:** ask "Restaurant or place?" for an Apple or Google Maps place ([3b868d3](https://github.com/JohnDuprey/kinwall-mobile/commit/3b868d3f0f1eda48312fa076c2ddb5f1dcec64a7))
* **share:** fill a new event's end from the family's usual event length ([071fbaa](https://github.com/JohnDuprey/kinwall-mobile/commit/071fbaa38bd979a216351ee2ec85bb1de3530296))
* **share:** read menu photos row by row, with their QR order links ([9a364e2](https://github.com/JohnDuprey/kinwall-mobile/commit/9a364e21a680dc92816d88fdf141b100db251e92))
* **share:** save events and places to Outings from the share sheet ([8779dce](https://github.com/JohnDuprey/kinwall-mobile/commit/8779dce704525420f5b345aeb2b7cd9b00b25d15))
* **share:** send a Maps place's phone, address and website with it ([ee52067](https://github.com/JohnDuprey/kinwall-mobile/commit/ee520673db44d5473148986788566e2534c1bfec))
* **share:** share several photos of a menu at once ([bedade7](https://github.com/JohnDuprey/kinwall-mobile/commit/bedade7dd24740faa2daf7720fc3fe6761e8f04b))
* **share:** show what will be saved before adding a recipe, restaurant or book ([14fc90d](https://github.com/JohnDuprey/kinwall-mobile/commit/14fc90da28338e3b2e798137e4013e802a1633a2))
* **shell:** speak words for activity plugins with the system voice ([ebaaebe](https://github.com/JohnDuprey/kinwall-mobile/commit/ebaaebe9a495a736a71c002415e323f6f07d3dfe))


### Fixed

* **android:** fill the notification icon's box so the logo isn't tiny ([d985181](https://github.com/JohnDuprey/kinwall-mobile/commit/d985181e6655244209d3023c4d0c87afdb5deb1c))
* **android:** show chores waiting for a parent's OK as ticked ([95326e1](https://github.com/JohnDuprey/kinwall-mobile/commit/95326e1f7d2121aed46cbcdfc1a9900dc15f4c7e))
* **android:** stop reopening the permission screen on every page load ([cc93359](https://github.com/JohnDuprey/kinwall-mobile/commit/cc93359068dc84edfd7cbc9a5cedff71f4b2829c))
* **android:** stop the Chores widget's ticks failing with a 400 ([f2e640d](https://github.com/JohnDuprey/kinwall-mobile/commit/f2e640db97b0f81793608cb1cd7adbe9cc194599))
* **auth:** re-read the saved sign-in before giving up on a refresh ([f99571c](https://github.com/JohnDuprey/kinwall-mobile/commit/f99571c83f6f24ac97ef68c7d519f6373efe1ebb))
* **ios:** ask to unlock before Siri, widgets or reminders change anything ([2010b18](https://github.com/JohnDuprey/kinwall-mobile/commit/2010b184c26c80bed24d8fc38cac2cad76a93b6a))
* **ios:** claim the audio only while a beep or a word plays ([bb6dd89](https://github.com/JohnDuprey/kinwall-mobile/commit/bb6dd89977df43b1d9ddc7602f31e3fd3bfe06e9))
* **ios:** honor Lists off in the Reminders schema and rename Open Groceries ([af30aed](https://github.com/JohnDuprey/kinwall-mobile/commit/af30aed58237f188357f349ba629e35021aa9705))
* **ios:** keep sign-ins and keys on this iPhone, out of backups ([c9ed396](https://github.com/JohnDuprey/kinwall-mobile/commit/c9ed3968487be143e303fafa00e6699738a95f8e))
* **ios:** keep the calendar in view and close the share sheet with an X ([68ec512](https://github.com/JohnDuprey/kinwall-mobile/commit/68ec5122e58c853b4c466e92cd249346df06dc2c))
* **ios:** make the share sheet's main buttons a solid blue ([8aa664a](https://github.com/JohnDuprey/kinwall-mobile/commit/8aa664a6f6bd494382abb300ca816117d05b0b0f))
* **ios:** show chores waiting for a parent's OK as ticked ([d8013b5](https://github.com/JohnDuprey/kinwall-mobile/commit/d8013b5e3e46d8e4cdd9667a0465aa944aefe027))
* **ios:** show the name under the logo on the splash screen ([5ba98a8](https://github.com/JohnDuprey/kinwall-mobile/commit/5ba98a8070f3e82bbc14c2255d5ba64b2c8864bf))
* **share:** keep a menu photo's prices on their rows and missed text ([5a2281a](https://github.com/JohnDuprey/kinwall-mobile/commit/5a2281add74e2da230b5c70574c4098f4c76bb9a))
* **share:** open the app when no calendar can take a shared event ([ceb594c](https://github.com/JohnDuprey/kinwall-mobile/commit/ceb594c2dd9d29e5179f781c7f386a603485d82d))
* **share:** refresh the sign-in once when the calendars and the event go together ([14c5306](https://github.com/JohnDuprey/kinwall-mobile/commit/14c5306b3de97c3a3ad349fb312f1026ac7ebe3a))
* **shell:** follow a widget link tapped twice in a row ([ab580a0](https://github.com/JohnDuprey/kinwall-mobile/commit/ab580a030859ff4529a1373325abac206b3b7292))
* **shell:** give a waking page 8 s to answer before restarting it ([0b0800b](https://github.com/JohnDuprey/kinwall-mobile/commit/0b0800b4a499412e65476367154274d5c3911ea4))
* **shell:** give the native screens' text links a 44pt touch target ([c29bf88](https://github.com/JohnDuprey/kinwall-mobile/commit/c29bf88135c5c1fbe3f128a4a40b4378fa2067eb))
* **shell:** keep the welcome screen still on rotation and fit it in landscape ([7f09c44](https://github.com/JohnDuprey/kinwall-mobile/commit/7f09c445462accbd80c626e3cb57d4c3e6587b66))
* **shell:** recover the web view instead of leaving a blank screen ([1ed1221](https://github.com/JohnDuprey/kinwall-mobile/commit/1ed122151da50bb78f2a312b079c07c2dc6fa007))
* **shell:** skip repeat key syncs and ignore route-change load starts ([a1e4676](https://github.com/JohnDuprey/kinwall-mobile/commit/a1e4676d9c38a6de886478f3486224f1e046be79))

## [1.1.0](https://github.com/JohnDuprey/kinwall-mobile/compare/v1.0.0...v1.1.0) (2026-10-02)


### New

* **android:** a notification channel per purpose, and buttons on reminders ([e74d555](https://github.com/JohnDuprey/kinwall-mobile/commit/e74d555c7c233db856c1b8c0ccfd6e485a1688f1))
* **android:** launcher shortcuts and Quick Settings tiles ([918a6d9](https://github.com/JohnDuprey/kinwall-mobile/commit/918a6d9c9cc0a5e70b95741e2b0c6f8d751fba14))
* **android:** on-time alarms with USE_EXACT_ALARM, and no overlay permission ([471c09b](https://github.com/JohnDuprey/kinwall-mobile/commit/471c09bade6112f2352513f96584302adc6cb741))
* **android:** open a shared contact in the page's import review ([6a17505](https://github.com/JohnDuprey/kinwall-mobile/commit/6a175052149fe305b9f7d041be03a22c4622ba5f))
* **android:** ring cooking timers when they're up ([85c4bcf](https://github.com/JohnDuprey/kinwall-mobile/commit/85c4bcf11d1470a9c31383ab47730a1f24d63d09))
* **android:** start a Google Meet video call from a contact's sheet ([c85a31c](https://github.com/JohnDuprey/kinwall-mobile/commit/c85a31c083dea5cbc48e37277ab72d8b0fe33e7f))
* **auth:** finish a Google or Microsoft sign-in handed back from the in-app browser ([042025e](https://github.com/JohnDuprey/kinwall-mobile/commit/042025ee878805be8bc3db5fe71d0fbbd1070b76))
* **brand:** app icon in Peacock colors ([4061284](https://github.com/JohnDuprey/kinwall-mobile/commit/4061284d900e929c4db992a784a9488e79706abe))
* **brand:** new Kinwall app icon, splash and notification icon ([2422c9a](https://github.com/JohnDuprey/kinwall-mobile/commit/2422c9a95efe892ca2184989dae2764b27f68e4e))
* **ios:** a Kinwall Focus filter for other people's reminders and the health widgets ([d76fa72](https://github.com/JohnDuprey/kinwall-mobile/commit/d76fa727695d7b6e923ffa457f8e4e86c333121b))
* **ios:** add a remembered grocery to Kinwall in one Siri sentence ([d49676b](https://github.com/JohnDuprey/kinwall-mobile/commit/d49676b21ee5b7d01dac9cc5d3d6af58d128c9d4))
* **ios:** hear "add garlic to the grocery list in Kinwall" and only say Added once saved ([1feb3c9](https://github.com/JohnDuprey/kinwall-mobile/commit/1feb3c9bc7eb61f3328ee7140cf0a78831cf9f90))
* **ios:** reminders with Snooze, Taken and Done, plus medicine reminders and a chore nudge ([88ce9a9](https://github.com/JohnDuprey/kinwall-mobile/commit/88ce9a93aa5bc6e97e0953360f5d121b99f4d040))
* **ios:** ring cooking timers with AlarmKit, or notifications before iOS 26 ([2905fe1](https://github.com/JohnDuprey/kinwall-mobile/commit/2905fe12fae6d0688415534225c044657b64ac49))
* **ios:** tint cooking timer alarms with the family's accent color ([99f91d8](https://github.com/JohnDuprey/kinwall-mobile/commit/99f91d86004a4b0f0a1548dc54bfec67a843af88))
* **native:** respect check-ins, Health and medicine switches ([5db0c99](https://github.com/JohnDuprey/kinwall-mobile/commit/5db0c99f02dcdf6d73acf49b06241670259ea8b6))
* **native:** respect the family's feature switches ([db03ea0](https://github.com/JohnDuprey/kinwall-mobile/commit/db03ea09f1871c3bd3dab50744b650234774f4ca))
* **share:** review and import a shared contact in the share sheet ([14bdbb9](https://github.com/JohnDuprey/kinwall-mobile/commit/14bdbb9c2d72251e12f759b044a2cd4deb0f0d28))
* **shell:** beep and tap on a successful barcode scan ([b86ab66](https://github.com/JohnDuprey/kinwall-mobile/commit/b86ab667fce525b19ad3914cf3de8edbd8c1cc68))
* **shell:** front camera for wall screens, a Flip button and a warmer beep ([717d6dc](https://github.com/JohnDuprey/kinwall-mobile/commit/717d6dc03f35b4b9904a890878f3dbb2506f059b))
* **shell:** offer the scanner for groceries as well as books ([0250bd3](https://github.com/JohnDuprey/kinwall-mobile/commit/0250bd35af2ed7510c55d6ae7ef60239c7fa0ad4))
* **shell:** paint the app's own screens in peacock, the new default ([b868d37](https://github.com/JohnDuprey/kinwall-mobile/commit/b868d372164962c591d63438edde1422dc0e3bc9))
* **shell:** scan barcodes with the camera for the web app ([be235fe](https://github.com/JohnDuprey/kinwall-mobile/commit/be235feef9456f6b933d82ce4414384afb74b2bf))
* **shell:** show the logo on the iOS splash screen ([fbe8606](https://github.com/JohnDuprey/kinwall-mobile/commit/fbe8606e85528a1f0719e1ce771b727b122c34fd))
* **widgets:** Android widgets in the family's colors, plus Chores, List and Take now ([980ec5d](https://github.com/JohnDuprey/kinwall-mobile/commit/980ec5d5f985f46c23672799854246b54f5b41e6))
* **widgets:** pick the Groceries list by its type ([6498bc4](https://github.com/JohnDuprey/kinwall-mobile/commit/6498bc4996548733e6f50fa34c8f32fc9f2cf7d1))
* **widgets:** small Live Activity layouts for the Apple Watch and CarPlay ([068624f](https://github.com/JohnDuprey/kinwall-mobile/commit/068624f772edace74764543e49d43ee4efef51a3))
* **widgets:** Smart Stack relevance for Now & Next, Take now, Chores and the Watch ([4a896ae](https://github.com/JohnDuprey/kinwall-mobile/commit/4a896ae6a195c4faa053d9e1e3e75e34c3676915))
* **widgets:** use the family's default Groceries list ([1c0a891](https://github.com/JohnDuprey/kinwall-mobile/commit/1c0a891bf86a3d80b75baa1e12add16f7820097d))


### Fixed

* **android:** open a vCard shared as text in contacts, not recipes ([a5219f7](https://github.com/JohnDuprey/kinwall-mobile/commit/a5219f7640287471c0d5a3b4884ef4b2d817eec1))
* **android:** tick the other list's items from the shopping notification ([524588a](https://github.com/JohnDuprey/kinwall-mobile/commit/524588ab28dfaed768df5d9e9775f3ed0b9482e1))
* **brand:** bump the iOS app icon's logo to 87% of the tile ([5c65315](https://github.com/JohnDuprey/kinwall-mobile/commit/5c65315621a6a608b437908b40458363bf89eaf7))
* **brand:** give the Android icon the same breathing room as iOS ([e896f2d](https://github.com/JohnDuprey/kinwall-mobile/commit/e896f2d519f319d777e6ebd66430441a1734cc12))
* **brand:** make the logo fill more of the iOS app icon ([5cf0ea0](https://github.com/JohnDuprey/kinwall-mobile/commit/5cf0ea051bc36c14bb78f2a39b600eb7a430cca3))
* **ios:** build each checkout into its own folder ([bfc38e4](https://github.com/JohnDuprey/kinwall-mobile/commit/bfc38e439dc8932ebf769005b8f32a220262b560))
* **ios:** don't let Siri add a second copy of what's on the list ([4d4053a](https://github.com/JohnDuprey/kinwall-mobile/commit/4d4053a0fc46776f5cb4c65c0423aed95177f8c2))
* **ios:** help Siri hear "Kinwall" instead of "quinoa" ([63665e6](https://github.com/JohnDuprey/kinwall-mobile/commit/63665e6994b05b491f137ec78514d24d5dc478fe))
* **ios:** stop Siri's intents crashing the app when Kinwall can't be reached ([aa9e28b](https://github.com/JohnDuprey/kinwall-mobile/commit/aa9e28bb4d2b0eea2dca309cbf6275247055a6c8))
* **ios:** tick the other list's items from the shopping Live Activity ([aa3271c](https://github.com/JohnDuprey/kinwall-mobile/commit/aa3271c937b0db3dbc9205b170d6288f0911ddd6))
* **native:** end cooking Live Activities that rang, were stopped or swiped away ([11a8c48](https://github.com/JohnDuprey/kinwall-mobile/commit/11a8c48759875fed2ea75b613572250f0740dcf0))
* **share:** say what's being opened and lay out a shared contact ([40576eb](https://github.com/JohnDuprey/kinwall-mobile/commit/40576ebf43158ed6fee9da35c93e9224c3dbdba6))
* **shell:** make the scan beep a little quieter ([c0721f7](https://github.com/JohnDuprey/kinwall-mobile/commit/c0721f74db5b67a61faa3540d9e76a27a76f2690))
* **shell:** make the scan beep quieter and lower ([0dfec65](https://github.com/JohnDuprey/kinwall-mobile/commit/0dfec6572febeee6753ae04943d8bdd739463696))
* **shell:** make the scan beep softer and play it in silent mode ([e3d71d4](https://github.com/JohnDuprey/kinwall-mobile/commit/e3d71d495f16df0eeafaabdc1dd7527a274f0dc7))
* **shell:** replace the widgets' key when it opens another household ([bdd632c](https://github.com/JohnDuprey/kinwall-mobile/commit/bdd632c81c0026eda3559a39cde5ef1f5a90ed08))
* **shell:** trust only the server's origin and this launch's bridge ([7d082db](https://github.com/JohnDuprey/kinwall-mobile/commit/7d082db01bfcfa9fdc48f1c6289b2628495f0d1c))
* **ios:** only say Added once the item is saved: Siri could say "Added garlic to Groceries" with nothing saved ([1feb3c9](https://github.com/JohnDuprey/kinwall-mobile/commit/1feb3c9bc7eb61f3328ee7140cf0a78831cf9f90))
* **widgets:** draw Live Activities on the system background, green only as an accent ([91c0d67](https://github.com/JohnDuprey/kinwall-mobile/commit/91c0d675c6ae438ecbec31965fe8e5403aa9b543))
* **widgets:** give the cooking Live Activity's recipe name room ([3128692](https://github.com/JohnDuprey/kinwall-mobile/commit/31286923950a62187cfb1c2ef231680cef219dab))

## [1.0.0](https://github.com/JohnDuprey/kinwall-mobile/compare/v0.1.0...v1.0.0) (2026-09-29)

The first release of the Kinwall app. It wraps your family's Kinwall (self-hosted, or any Kinwall
server) in a native app, and adds the things a web page can't do: widgets, Live Activities, Siri,
a Watch app and more. No account needed to look around: tap **Try the demo** on the first screen.

### The app
* **Sign in to your family's Kinwall**, or **Try the demo** with a sample family (widgets and
  reminders included), right from the first screen.
* **Starts in your family's colors**, light or dark, with no white or peach flash on launch, and
  no sign-in screen flicker when you're already signed in.
* **Share a recipe to Kinwall** from Safari, Chrome or any app (iOS and Android share sheet): it
  checks the recipe reads correctly and asks before importing.
* Keeps the screen on in shopping mode and while a recipe is open.
* Web links open in an in-app browser; the back button (Android) steps back through Kinwall.

### Live Activities (iPhone) and ongoing notifications (Android)
* **Cooking timers**: the step's timer counts down on the Lock Screen and in the Dynamic Island,
  then says "Done".
* **Shopping trips**: the store, how many are left, the next item and where it is ("Dairy · then
  Dishwasher tablets (Aisle 17)"); tick it off with **Got it** without opening the app.
* **Leave by / start prep by**: a countdown to when you need to leave, or start cooking a meal,
  with friendly, varied reminders.
* **Medicine that's due**: "Still time for Maya's medicine · until 8 PM" with **Taken** and
  **Snooze**. Generic on the Lock Screen unless the device turns names on.
* On Android, leave-by countdowns are scheduled on the phone, so they appear even with the app
  closed.

### Widgets and Controls
* Home Screen widgets for today, chores and lists; **tick a chore or list item right from the
  widget**.
* **Lock Screen widgets**: next event, chores left, and a Take now medicine widget with Taken.
* **Daily check-in widget**: answer "How did you sleep?" and "How are you feeling?" with a tap;
  the evening goal check and "How drained do you feel?" in the evening.
* **Energy battery widget**: today's level and what's behind it (Lock Screen: a gauge only).
* A **StandBy clock** with the next event for a phone charging on the nightstand.
* **Controls** (iOS 18) for Control Center, the Lock Screen and the Action button: Add to
  Groceries, Start shopping, Night screen.

### Siri, Shortcuts and Spotlight (iPhone)
* "Add milk to Groceries", "What's on today?", "What's next?", "Start shopping at the market",
  "Mark Leo's chore done", "Start the night screen".
* Search your family's recipes, lists and contacts from Spotlight; a tap opens them in Kinwall.

### Apple Watch
* Today, your chores, and a **Take now** page with Taken and Snooze.
* **A gentle three-tap buzz** at each transition warning ("leave in 10 minutes").
* One-tap sleep check-in, and complications for the next event, chores left, medicine due and your
  energy battery.

### Privacy
* Health information (medicines, check-ins, the energy battery) stays on the person's own device
  and parents' devices, is generic on the Lock Screen unless you turn names on, and is never on a
  shared wall.
* Privacy manifests for the app and every extension; how to delete your family's data is in
  iPhone Settings → Kinwall.

### Good to know
* These are **test builds** (see "Install a test build" below). The App Store and Google Play
  versions come later.
* Countdowns that start while the app is closed on iPhone, and native push notifications, need the
  store version; everything above works without them.
* The newest features (Live Activities for
  medicine, start prep by, varied reminders) need an up-to-date Kinwall server.
