# Widgets, Apple Watch and Siri: feature ideas

A menu for M3 (widgets), M4 (Watch) and M5 (Siri), built on things Kinwall already does. Each idea is tagged:

- **First:** worth doing in the first pass.
- **Later:** a good follow-up.
- **Paid:** needs the paid Apple Developer membership (M6).

## Things that shape every feature

- **Widgets and the Watch get their own key.** An OAuth key that refreshes and rotates can't safely be shared between the app, a widget and a watch, because two refreshers would end the grant. Instead, the signed-in app creates a separate everyday-access key for its widgets ("Widgets on this iPhone") and one for the Watch. Each can be revoked on its own under Settings → Access. This needs a small server route that lets an OAuth-signed-in app mint a display key for itself.
- **Sharing that key with the widget** needs a shared Keychain group. Whether a free Personal Team allows that is still to be confirmed (see PLAN.md). If it doesn't, each widget pairs itself once with a code.
- **Local notifications work without the paid account.** The app can schedule reminders on the device from the data it already has: event reminders, leave-by times and the chore nudge. On iPhone, that gives the app real reminders before APNs push exists. The Watch mirrors iPhone notifications automatically.
- **Widgets update on a budget,** about every 15 to 60 minutes, plus right away after a tap inside the widget. Countdowns ("in 12 min") use the system's live timer text, so they tick without refreshes.
- **What the family turned off stays off.** Kinwall's Settings → Features (`GET /api/settings` `features`; a switch an older server doesn't send counts as on) reaches every native surface, with no extra cache: each widget fetch asks for the settings too, and the app redraws the widgets when it sees the switches change (`src/spotlight.ts`). Chores off: the Chores widgets and the Watch's My chores say "Chores are turned off in Kinwall", the Chores-left rings read "Off", Today and Siri's "What's on today" leave chores out, and "Mark a chore done" answers "Chores are turned off in Kinwall." Lists off: the List widgets and the Watch's Lists say so, Siri's Add to a list, Add to Groceries and Start shopping answer "Lists are turned off in Kinwall." and save nothing, the Add to Groceries and Start shopping controls (and Android's Groceries shortcut and tile) just open the app, and Spotlight drops lists. Meals and Contacts off: Spotlight drops recipes or contacts. Check-ins off: the Daily check-in and Energy battery widgets and the Watch's Check-in say "Check-ins are turned off in Kinwall", and the battery gauges read "Off". Medicine shows only with medication reminders on and the Health tracker on (settings `medications` and `features.trackersHealth`, as the server decides); otherwise Take now (iOS, Android, the Watch screen and complication) says "Medicine is turned off in Kinwall" or "Off". Rewards appear nowhere natively, so `rewardsEnabled` has nothing to hide. The Live Activities (cooking, shopping, leave-by, medicine) are started by the web app, which doesn't offer what's off.
- **"Who am I" on a device.** A watch, or a widget set to one person, knows whose chores to show and who gets the points for an Anyone chore. That removes the "Who did it?" question wherever the answer is obvious.

## Widgets (iPhone and iPad)

### Home Screen

| Widget | Sizes | What it shows | Tag |
|---|---|---|---|
| **Now & Next** | Small, medium | What's on now, what's next, and a live "leave in 12 min" countdown. Surfaces itself in the Smart Stack as leave-by nears. | First |
| **Today** | Medium, large | A small Board: today's events, chores left per person, what's due. | First |
| **Chores** | Small to large, interactive | Everyone, one person (with or without Anyone chores), or only Anyone chores, with a tap to tick off. Set to a person, it credits them for Anyone chores; otherwise an Anyone chore opens the app to ask who did it. A chore with an open checklist opens the checklist in the app. The small size uses the chore's emoji as the checkbox so titles get two lines. | First |
| **List** | Medium, large, interactive | A chosen list, Groceries by default (`FamilyList.groceries`: the family's default Groceries list, else the first Groceries-type list, else one named Groceries, else the first shopping list; Siri and the controls pick the same way): tick items off in the widget. **Add** opens a quick-add in the app. | First |
| **Leaderboard** | Small, medium | This week's points and streaks. Motivating on a kid's iPad. | Later |
| **Family photo** | Small to large | A rotating picture from the family album, like the Board's photo card. Great in StandBy. | Later |
| **Countdown** | Small | Days until a chosen event or the next birthday ("Beach trip in 12 days"). | Later |
| **Week** | Large, extra large (iPad) | The next seven days as a list. | Later |

### Lock Screen

| Widget | What it shows | Tag |
|---|---|---|
| **Next event** (inline and rectangular) | "Soccer · 4:00 · leave 3:40" | First |
| **Chores left** (circular) | A ring filling as today's chores get done | First |
| **Take now** (circular, rectangular, inline) | Medicines due now: how many, and whose. Names stay "Medicine" unless the widget's **Show medicine names** is on and the server shares names with this device (a person's own device, or a wall with names on) | Built |
| **List count** (circular) | Open items on Groceries | Later |
| **Points** (circular) | My points this week | Later |

### StandBy and nightstand

**Clock & next** (small) is made for StandBy: a big clock (one timeline entry a minute from a single fetch) and what's next, with the leave-by time. The other small widgets work in StandBy too. The Family photo and Now & Next widgets suit a charging iPhone on the kitchen counter.

### Controls (Control Center, Lock Screen, Action button)

| Control | What it does | Tag |
|---|---|---|
| **Add to Groceries** | Opens Groceries in the app, at its add field (a control can't take typing). In Shortcuts its action is **Open Groceries**, so it isn't confused with Siri's Add to Groceries, which adds the item | Built |
| **Start shopping** | Opens shopping mode on Groceries | Built |
| **Night screen** | Opens the app on the dim night clock | Built |

Built 2026-09-29 in `targets/widgets/Controls.swift` (iOS 18 and later; on iOS 17 they aren't offered). Each runs an open-the-app intent from `native/ios/OpenIntents.swift`, compiled into the app and the widget extension, so iOS runs it in the app. They work from Control Center, the Lock Screen's control slots and the Action button. Checked in the Simulator: all three are offered under Kinwall in Control Center, and Night screen opens the night clock. A one-line quick-add without opening the app would need Kinwall's own small add screen; the web app's list is the add screen for now.

### Live Activities

Built (2026-09-29), in `targets/widgets/LiveActivities.swift`, started by the app from the web app's messages (`modules/kinwall-native/ios/LiveActivities.swift`; the web app decides what they say, `web/src/liveActivity.ts` in kinwall). One `KinwallActivityAttributes` type for all three (`modules/kinwall-native/ios/KinwallActivityAttributes.swift`, compiled into the widget extension too). No Kinwall setting: iPhone **Settings → Kinwall → Live Activities** turns them off, and the web app's Notifications section says which.

| Activity | What it does | Needs |
|---|---|---|
| **Cooking timer** | Starts with a step timer in cooking mode: the timer's name as the headline ("Rice"), the recipe in full and the step ("Step 3 · Simmer · +1 more"), and a countdown (`Text(timerInterval:)`). In the expanded Dynamic Island only the icon sits beside the camera and the countdown on the right; the headline, recipe and step get the full width below (two lines, shrinking a little before they're cut). When it's up it says "Done: Chicken" (it goes stale at the timer's end, so no update is needed). Once the page says it rang, the app ends it: out of the Dynamic Island at once, and off the Lock Screen 5 minutes later (`dismissalPolicy: .after`), even if cooking mode is never opened again. **Stop** on the timer's alarm ends it at once, with the app closed too (see below). Swiped off the Lock Screen, it stays gone: the page catching up with the same timers ("Done: Chicken") doesn't bring it back; a new timer, or one paused and resumed, does. Gone too when the timer is dismissed or cooking mode closes, including a stale one or one from an earlier launch. Each running timer also rings when it's up (see [Cooking timers that ring](#cooking-timers-that-ring)). A debug build shows a sample from `family.kinwall.app:/open?to=calendar&debug=cooking`. | Nothing: local |
| **Shopping trip** | Starts with a trip (Shop, or shopping mode): the store and how many are left on top, the item to get now in large type, and under it where that item is and what's after it ("Dairy · then Dishwasher tablets (Aisle 17)", "then Milk (same aisle)", or "Dairy · last one!"), in walking order. A long next item is shortened, never the aisle. **Got it** ticks that item (`GotItIntent`, `native/ios/LiveActivityIntents.swift`) with the widgets' own key from the shared Keychain group, then moves on to the next of the five items it carries. On a combined trip (Groceries and Shopping lists at one store) an item from the other list carries that list's `listId`, and Got it ticks it there; **Open** opens shopping mode (`family.kinwall.app:/open?to=lists/<id>/shop`). The page updates it on every change; Checkout or End ends it. | Nothing: the shared Keychain group, no App Group |
| **Medicine due** | A dose that's due, or still inside its late window, on the person's own phone (walls never get one): 💊 and the web app's label on top ("Maya's medicine", generic unless the device opted into names; the app never adds a name), its headline in large type ("Time for Maya's medicine", "Still time for Maya's medicine"), "Due now · still time until 8:00 PM" with a countdown to the window's end, and **Taken** / **Snooze 10 min** (`MarkDoseActivityIntent`, `POST /api/medications/{id}/doses` with `{ date, time, action }`, `time` possibly `wake`, with the widgets' key, so a person's own phone marks only theirs). Kind words only, never "missed". Both buttons end it; after a snooze the web app starts it again when it's due. It also goes at the window's end. Payload (kinwall `tellAppActivity('medication', …)`): `{ medicationId, date, time, memberName, label, headline, dueAt, windowEndsAt, stage: 'due' \| 'late' }`. A debug build shows a sample (the demo family's Sam) from `family.kinwall.app:/open?to=calendar&debug=medication`. Checked in the Simulator with the sample; the buttons against a real dose are build-only here. | Nothing: the shared Keychain group |
| **Leave by / start prep by** | The device's person's next leave-by or start-prep time (a meal's event), from their first transition reminder until the event starts: a varied headline ("Sam, leave for Piano Lesson at 10:55 AM 🚙") and a countdown, then "Leave now" once it's time (stale date). Only on a phone that belongs to someone with transition reminders on and notifications allowed. | Local while the app is open; Apple push (paid) while it's closed |

**Colors (2026-10-02):** every activity draws on the system's own Lock Screen background (light or dark with the phone, `activityBackgroundTint(nil)`) with the system's primary and secondary text, as the Dynamic Island does on black. Kinwall's blue (Peacock, the default scheme) is only an accent: the countdown or count, a headline once it's due, and the main button (**Taken**, **Got it**, tinted); **Snooze 10 min** and **Open** are gray. The deep peacock (`#123857`, 10.9:1 on the light card) in light mode, the sky blue (`#6CB4EE`, 7.6:1 on the dark card, 9.4:1 on black) in dark mode and in the Dynamic Island. The family's frame background no longer fills the card.

**Apple Watch and CarPlay (built 2026-09-30):** from iOS 18 every activity also has a small layout (`supplementalActivityFamilies([.small])`, `SmallActivity`): the icon, the countdown or count, and the headline, with no buttons. iOS 18 shows it in the Apple Watch Smart Stack, and iOS 26 on the CarPlay Dashboard, which otherwise get a generic one. A medicine shows the web app's headline, never the medicine's name. On iOS 17 the activities are as before. Build-only so far: the Simulator has no paired-Watch or CarPlay view of a Live Activity.

Checked in the iOS 27 Simulator (iPhone 17 Pro) with the demo: all three start and show on the Lock Screen and in the Dynamic Island (compact, minimal, expanded), countdowns tick, and **Got it** moves the trip on. In that Simulator iOS runs Got it in the widget extension rather than the app, so both copies of the intent do the whole job. `xcrun simctl push` delivered a push-to-start payload only as a plain notification (no Live Activity), so push-to-start is checked by the server's tests, not end to end.

#### Cooking timers that ring

Built (2026-09-30), in `modules/kinwall-native/ios/CookingAlarms.swift`. The cooking payload carries `alarms`, every running timer's finish (`[{ at, title: "Time's up: Rice", body: "Chicken curry · Step 3 · Simmer" }]`, kinwall `cookingActivity()`); paused and done timers aren't in it. Each payload replaces the last set, so the page stays the source of truth: pause, reset or cancel takes a timer out, and resume puts it back with its new finish. A timer is known by its finish and title (a hash of both is its id), so a payload that didn't change it leaves it alone. The alarms go even with Live Activities turned off.

- **iOS 26 and later:** the first time a cooking timer runs, the app asks to use alarms (`NSAlarmKitUsageDescription`), and once allowed each finish is an AlarmKit alarm, which rings like the Clock app's timer through silent mode and Focus. It's an alarm at a fixed time, not an AlarmKit countdown, because the cooking Live Activity already counts down on the Lock Screen and in the Dynamic Island; a countdown would show a second one, and needs a widget of its own. So the system shows only the alert, with **Stop**, which dismisses it, tinted with the family's accent color (the colors the page sends with its Live Activities; Kinwall's own accent without them). There's no Pause or Resume in the system UI, so nothing there can fall out of step with the page. A timer that's ringing keeps ringing until Stop, unless cooking mode is on screen (the page beeps and marks it done, and the app stops the alarm) or closes. AlarmKit needs no entitlement or capability, so it works on the free Personal Team; `AlarmKit` is weak-linked for iOS 17 to 25.
- **iOS 17 to 25, or alarms not allowed:** a local notification at each finish with the payload's title and body and the default sound (id `cook:…`; all of them are canceled and scheduled again on every payload). While the app is open they're hidden (`src/reminders.ts`), since cooking mode beeps. They follow the phone's silent switch and Focus like any notification.
- **Stop ends the Live Activity:** each alarm carries a stop intent (`StopCookingTimerIntent`, `native/ios/LiveActivityIntents.swift`, app only; the native module gets it through `CookingAlarms.stopIntent`, set at launch by `AppHooks`). iOS runs it in the app even while it's closed, and it ends the cooking activity showing that timer, which the page, suspended in the background, couldn't. Alarms set before this change have no stop intent; their activity goes when the page next says the timer rang.
- **Ending:** closing cooking mode (the web's end message) and sign-out cancel them all and stop one that's ringing.
- **The demo** rings its sample timers; the payload has only the recipe, timer and step names the Live Activity already shows.

Checked: the native module builds against the iOS 27 Simulator SDK. Needs a real phone: the AlarmKit prompt and alert, ringing on silent, Stop, and a timer paused or reset on the page before it's up.

## Apple Watch

### The app

| Screen | What it does | Tag |
|---|---|---|
| **Today** | Now & Next with the leave-by countdown, then the rest of today. Tap an event for its details, and its location opens Maps. | First |
| **My chores** | This watch's person's chores for today. Tap to tick off. Anyone chores count for them. Checklist steps can be ticked one by one. | First |
| **Lists** | Groceries and others. Big rows to tick off while shopping, with the phone in a pocket. Add by dictation or Scribble. Works offline and syncs when back in reach. | First |
| **Points** | My points, streak and sticker balance. | Later |
| **Messages** | The notification feed (the bell), including family messages. | Later |
| **Family** | Who has what today, one line per person. | Later |

### Complications and the Smart Stack

| Complication | Tag |
|---|---|
| **Next event** with the leave-by countdown, surfacing in the Smart Stack as it nears | First |
| **Chores left** as a gauge | First |
| **Take now:** how many medicines are due (circular, inline, corner), never their names | Built |
| **Groceries** open count (with watchOS 26's grocery-store relevance, `RelevantContext.location(category: .foodMarket)`, so it comes up in a store with no location permission) | Later |
| **Points** this week | Later |

**Relevance (built 2026-09-30):** Next event rises in the Smart Stack over the hour before the next leave-by time (or start), and Take now while a dose is due (`TimelineEntryRelevance`, watchOS 10 and later, so watchOS 26 too). A watchOS 26 `RelevanceConfiguration` widget isn't needed for that; the grocery-store context waits for a Groceries complication.

### Watch-only touches

| Idea | Tag |
|---|---|
| **Double tap** (Series 9 and later) ticks off the top chore or list item on screen | Later |
| **Haptic transition warnings:** a tap on the wrist before the next event, like the wall's transition warnings, from local notifications | Built |
| **A child's watch without an iPhone** (Apple's Family Setup): the watch pairs itself with a code an admin approves, the same flow as a wall display. Chores, points and Now & Next, all on the wrist. | Later |

## Siri, Shortcuts and Spotlight (App Intents)

These run on iPhone, iPad and Watch, and power the interactive widgets too.

| Intent | Example | Tag |
|---|---|---|
| **Add to a list** | "Add to Groceries in Kinwall" or "Add to the grocery list in Kinwall", then "Eggs" (Siri asks for the item: an App Shortcut phrase can't hold free text) | First |
| **Add a grocery in one sentence** | "Add milk to the grocery list in Kinwall", for groceries the family has added before | Built |
| **Add anything in one sentence** (iOS 27, Apple Intelligence's Siri) | "Add garlic to the grocery list in Kinwall", any item, through the Reminders app schema | Built |
| **What's next** | "What's next on Kinwall?" | First |
| **What's for dinner** | "What's for dinner in Kinwall?" | Built |
| **Log reading** | "Log reading in Kinwall", then the book and the pages | Built |
| **Vote in a poll**, **Add an event** | Shortcuts actions | Built |
| **Complete a chore** | "Mark Take out trash done" | First |
| **Points** | "How many points does Maya have?" | Later |
| **What's on** a day | "What's on Kinwall tomorrow?" | Later |
| **Spotlight** | Recipes, lists and contacts searchable from the Home Screen | Built |
| **Action button** (iPhone 15 Pro and later, Watch Ultra) | Mapped to "Add to Groceries" | Later |

## Status

- **Built and checked in the Simulator:**
  - Now & Next, including the Lock Screen versions.
  - Today.
  - Chores left, as a ring.
  - Chores (interactive): Person (Everyone or one person), Include Anyone chores, and Only Anyone chores, which hides the other two. Tapping a chore completes it on the server. Set to a person, it credits them for Anyone chores; otherwise an Anyone chore opens the app on "Who did it?". A chore with an open checklist opens that checklist in the app.
  - List (interactive).
  - The widgets' own key, created with the server's device-key route and revoked on sign-out.
  - The demo: while **Try the demo** is open, every widget shows built-in sample data for the demo family, marked Demo (src/demo.ts sets `SharedKeychain.demoStore`; a real family's key always wins). Tapping a sample chore or item opens the demo instead of ticking it. Not yet checked on a device.
- **Widget settings use only strings and switches.** In the Simulator, a custom AppEntity or AppEnum saved in a widget's settings read back empty, so the person and the list are saved as ids chosen from a dynamic options list. Switches can hide rows (Only Anyone chores hides Person); a string or enum choice can't be relied on for that.
- **Event reminders on the device:** the app schedules each event's reminders (its own times, or the household default) as local notifications for the next 48 hours, with the same wording as the server's push, and a tap opens the event. It refreshes when the app opens, goes to the background, and a few times a day in the background. Checked in the Simulator: permission is asked right after sign-in and a reminder arrives on time with the server's wording. Every event is included for now; the per-person filter that web push has is a follow-up (the Focus filter below can quiet other people's).
- **Reminders with buttons (iPhone, built 2026-09-30):** `src/reminders.ts` sets three notification categories, and `native/ios/NotificationActions.swift` runs their buttons in the background without opening the app, with the widgets' own key (a delegate of expo-notifications' `NotificationCenterManager`, registered at launch in `AppHooks`):
  - **Event reminders:** **Snooze 10 min** (a copy 10 minutes later, id `snz:…`, which a refresh leaves alone and sign-out clears) and **Open** (opens the event, like a tap).
  - **Medicine reminders:** new on the device. On a person's own iPhone (the widgets' key's owner, `GET /api/me`), each dose of theirs still to come today (`GET /api/members/{id}/medications?days=1`, the server's own times) and tomorrow's from the schedule, at its time: "Time for your medicine", "8:00 AM dose". Never the medicine's name: the per-device names choice lives with the web push settings, which the app can't read, so the Lock Screen stays generic. "When I start my day" doses are left out (the device can't know when the day starts). **Taken** and **Snooze 10 min** are the Live Activity's `MarkDoseActivityIntent` (`POST /api/medications/{id}/doses`), which also ends that dose's Live Activity; a snooze also brings the reminder back in 10 minutes.
  - **Chore nudge:** new on the device, off by default: iPhone **Settings → Kinwall → Chore nudge** and its time (7:00 AM to 7:00 PM). Once a day, on a person's own iPhone, the server's wording ("2 chores left today", the first three titles). **Done** only when it's a single chore without an open checklist (`POST /api/chores/{id}/complete`); otherwise a tap opens Chores.
  - If Taken or Done can't be saved (offline, signed out), the reminder comes straight back with "Didn't save. Try again, or open Kinwall." A saved one reloads the widgets.
  - **Time Sensitive** (leave-by and medicine break through a Focus and the Scheduled Summary): needs the `com.apple.developer.usernotifications.time-sensitive` entitlement, which the Personal Team's profile doesn't carry (checked 2026-09-30: signing with it fails, "Provisioning profile … doesn't include the Time Sensitive Notifications capability"). So it's off by default: `KINWALL_PUSH=1` (a paid team) or `KINWALL_TIME_SENSITIVE=1` at prebuild adds the entitlement and sets `KinwallTimeSensitive` in Info.plist, and only then does `modules/kinwall-native/ios/Reminders.swift` mark them `.timeSensitive`. Without it they're ordinary notifications.
  - Android has the same buttons, medicine reminders and chore nudge (built 2026-09-30): see [Android](#android).
  - Build-only so far; to check on an iPhone: each button from the Lock Screen with the app closed, a failed Taken in airplane mode, and the chore nudge setting.
- **Focus filter (iPhone, built 2026-09-30):** iPhone **Settings → Focus → a Focus → Add Filter → Kinwall** (`native/ios/FocusFilter.swift`, `SetFocusFilterIntent`, no entitlement). Two switches:
  - **Only my reminders:** event reminders for events that have people tagged and don't include this iPhone's person are tagged `others` (`filterCriteria`, set by `Reminders.swift` after scheduling) and the filter's `notificationFilterPredicate` keeps them quiet. Family events (nobody tagged) and medicine, chore and cooking notifications always come through. Now & Next and Today show only this person's events and family ones. A shared iPhone (no person) is unaffected.
  - **Hide health widgets:** Take now, Check-in and Energy show "Hidden during this Focus".
  - Saved as KinwallKit `FocusSettings` in the shared Keychain group (`family.kinwall.focus`), which the widgets read; iOS runs the filter again with both off when the Focus ends, which clears it. Build-only so far.
- **Smart Stack relevance (iPhone, built 2026-09-30):** Now & Next (and Today and Chores left, which share its entries) rise over the hour before the next leave-by time or start; Take now is up top while a dose is due (and not while a Focus hides it); Chores rises a little while any are left (`TimelineEntryRelevance`).
- **Watch app (first pass):** the iPhone app creates an "Apple Watch" key and sends it over WatchConnectivity; the Watch keeps it in its own Keychain. Screens: Today (Now & Next with the countdown, then later today), My chores (asks whose Watch it is once, Anyone chores count for that person, haptic on tick), Lists (tick items, add by dictation or Scribble). Checked in the Simulator: the key arrives from the iPhone, Today shows live data, a chore ticked on the Watch is credited to the Watch's person, and list items tick off.
- **Watch complications:** Next event (rectangular with the leave-by countdown, inline, corner) and Chores left (circular gauge), reading the Board with the Watch's key from the shared Keychain group. Built and embedded; not yet placed on a watch face in the Simulator.
- **Siri and Shortcuts (built 2026-09-29):** App Shortcuts that work without setup, in `native/ios/SiriIntents.swift`, with lists, people, today's chores and stores as entities Siri can match in a phrase (by their plain name too, without the emoji):
  - **Add to a list:** "Add to Groceries in Kinwall", "Add something to Groceries in Kinwall", "Add to the grocery list in Kinwall", "Add something to the grocery list in Kinwall", "Add to my Kinwall list" or "Add something to Kinwall" (Siri asks what to add; Groceries unless you name another list).
  - **Add to Kinwall (built 2026-10-07):** a Shortcuts and share action with no Siri phrase (it needs a photo or text, which Siri can't take by voice; its old phrase "Add to Kinwall with Kinwall" was dropped on 2026-10-08 to free the slot). The Shortcuts action takes **What it is** (Automatic, Recipe, Restaurant, Book, Event), a **Photo** (an `IntentFile`; Shortcuts' image-only filter is iOS 18+) **Text or link** (a `String`, which Shortcuts fills from URLs too) and an optional **Calendar** (an entity listing the calendars the app's sign-in can add to; with one, an event is saved there with `save: true`), sends them to `POST /api/share` as the share sheet does (barcode, Vision, the Apple Intelligence guess, else "What is this?"), signed in as the app is (never the widgets' key), and returns Kinwall's line as the dialog and a `family.kinwall.app:/open?to=shared&link=…` URL that opens the app at it.
  - **Add a grocery in one sentence (built 2026-09-30, phrases widened the same day):** seven phrases, each adding to Groceries and saying "Added Milk to Groceries.":
    - "Add milk to Kinwall"
    - "Add milk to my Kinwall list"
    - "Add milk to the grocery list in Kinwall"
    - "Add milk to my grocery list in Kinwall"
    - "Add milk to groceries in Kinwall"
    - "Add milk to the shopping list in Kinwall"
    - "Put milk on the grocery list in Kinwall"

    Siri's flexible matching (iOS 17 and later, not on Apple Watch) also takes close wordings of these. It works only for items the family has added before: an App Shortcut phrase can hold an entity but never free text, so the item is an `ItemEntity` from the groceries catalog (`GET /api/lists/remembered`, which the widgets' key may read). Siri gets the 111 most used (`RememberedItem.siriCap`, then the most recent), each answering to its name without the emoji ("Milk 🥛" is "milk"). Apple allows 1,000 App Shortcut phrases per app and language, each parameter value counting once per phrase it's in. KinwallKit's `SiriBudget` keeps the total at 900 or less: 20 plain phrases, 2 list phrases × 20 lists, 1 store phrase × 20 stores, 1 chore phrase × 40 chores (the entity queries suggest at most those), and the 780 left over split across the 7 item phrases, 111 items each. Its phrase counts must match `KinwallShortcuts`; a test checks the sum. Siri refreshes them at launch and whenever the app comes back (`updateAppShortcutParameters()`), live from the server like the other entities. A new item, or one past the 111, uses "Add to the grocery list in Kinwall" and then the item (or, on iOS 27, the Reminders schema below). The add is the normal list add, so the server fills in the remembered store and aisle; nothing edits the catalog (a kid's device can add without changing it).
  - **Any item in one sentence, iOS 27 (built 2026-09-30):** `native/ios/ReminderSchema.swift` adopts Apple's Reminders app schema (`@AppIntent(schema: .reminders.createReminder)`, with Kinwall lists as `.reminders.list` entities and items as `.reminders.reminder`). That's the one supported way for Siri to pass free text in a single sentence: Apple Intelligence's Siri understands "Add garlic to the grocery list in Kinwall" itself and hands over "garlic" and the list, matched on its name ("grocery list" finds Groceries), Groceries when no list is named. It needs iOS 27 with Apple Intelligence's Siri on; it's compiled only by Xcode 27 (Swift 6.4), so older Xcodes build the app without it. The schema's other fields (notes, due date, flags, tags, sections, location) are accepted and left out. Siri confirms on its own once the intent returns, so the intent returns only after the server hands back the new item.
  - **"Added" means saved (fixed 2026-09-30):** the adds now go through `KinwallClient.addItem`, which returns only when the server answers with the item on that list and otherwise throws "Kinwall didn't save it. Try again in the app." The demo no longer says "Added": it says the item wasn't saved and to sign in. And a Keychain read that fails no longer counts as "signed out" for the demo check (`DemoFamily.isOn(family:demo:)`), so a real family's Siri add can't quietly fall into the demo. Signed out, Siri says "Kinwall isn't signed in on this iPhone." The Watch's list add works the same way: a failed add keeps the text, shows why in red and buzzes.
  - **No doubles (2026-09-30):** the Siri adds (both App Shortcuts and the iOS 27 schema) send `?skipExisting=1` (kinwall servers from 2026-09-30 on; older ones just add). An item already open on the list isn't added again: Siri says "Garlic is already on Groceries." A ticked one is unticked: "Added Garlic back to Groceries." So "Add water and garlic to the grocery list in Kinwall" with garlic there adds only water. The Watch's and the app's own adds are unchanged.
  - **Who added it:** on a grown-up's phone the widgets' key is shared (the widgets show the whole family), so Siri's adds used to show "Widgets on iPhone". The server now credits them to the grown-up whose sign-in made the key (when their phone knows **Whose device is this?**), the Watch's too, without making the key theirs; nothing to do on the phone. A kid's phone already credited the kid.
  - **How Siri hears "Kinwall" (2026-09-30):** Siri kept hearing "quinoa". The app's Info.plist (app.json `ios.infoPlist`) now has `CFBundleSpokenName` "Kin Wall" and two `INAlternativeAppNames`, "Kin Wall" (hint "kin wall") and "Kinwall app" (hint "kin wall app"). Apple: App Shortcut phrases' `${applicationName}` matches the app's name and its synonyms (WWDC22 "Implement App Shortcuts with App Intents"; Technical Q&A QA1950 for the keys, "a small number" of alternatives, never the display name itself). Apple doesn't say whether synonyms count toward the 1,000-phrase budget; if Siri drops phrases, that's the first thing to check.
  - **The widgets' key follows the family (fixed 2026-09-30):** the app used to keep the widgets' key (which Siri, the widgets and the Watch use) whenever it was for the same server, so after signing in to another household on that server Siri could add to the old one. `ensureWidgetKey` (`src/sharedKey.ts`) now asks `GET /api/me` with both keys and mints a new one, revoking the old, when the `householdId`s differ (kinwall servers from 2026-09-30 on) or the old key gets a 401; the Watch's key is replaced with it. Offline or an older server without `householdId`, the key is kept. `widgetKeyFits` in `src/api.ts`, tested in `test/widgetKey.test.ts`.
  - **What's on today:** "What's on today in Kinwall" says what's left of today and how many chores are left, and shows it as a list.
  - **What's next**, as before.
  - **Start shopping:** "Start shopping in Kinwall" or "Start shopping at Neighborhood market in Kinwall" opens shopping mode on Groceries. The store rides along as `?store=` (the web app asks for the store until it reads that).
  - **Mark a chore done:** "Mark Water plants done in Kinwall", with an optional **Who did it** that gets the points for an Anyone chore. The server's rules for the widgets' key apply: a device that belongs to one person can only tick theirs, and Kinwall's refusal is read out. That key is everyday access, so a chore that needs a parent's OK waits for one: Siri says "Marked Dishes done. It's waiting for a parent's OK.", and the chore drops out of Siri's list. The Chores widget and the Watch's My chores show such a chore ticked too (`ChoreDay.pending`, `isTicked`), so it isn't ticked twice.
  - **Start the night screen:** "Start the Kinwall night screen" opens the app on the dim night clock (the event the header's 🌙 button sends).
  - **What's for dinner (built 2026-10-08):** "What's for dinner in Kinwall" or "What's for dinner tonight in Kinwall" (`native/ios/FamilyIntents.swift`) reads today's meals from `GET /api/board?days=1` (`Board.meals`) and says tonight's dinner: "Dinner tonight is Tacos, at 6:00 PM." On an order night it names the restaurant from the binder (`GET /api/restaurants/{id}`) and how: "Dinner tonight is pickup from Pizza Palace." (delivery, "out at" for eating there). With no dinner planned it says the next meal still ahead today ("Nothing's planned for dinner tonight. Next today: Grilled cheese for lunch."), else "Nothing's planned for dinner tonight." With Meals off: "Meals are turned off in Kinwall." Read-only, with the widgets' key. The wording is KinwallKit `Dinner.spoken`, tested in `FamilyActionsTests`.
  - **Log reading (built 2026-10-08):** "Log reading in Kinwall" or "Log my reading in Kinwall", then the **Book** (a `BookEntity`: the books someone is reading, `GET /api/trackers?kind=reading`, with the reader's name under each; on a device that belongs to someone, only theirs) and **Pages or minutes** (Siri asks "How many pages did you read?", or minutes for an audiobook). It moves the place in the book on (`PATCH /api/trackers/{id}`; the server logs the day) and says "Logged 20 pages of Holes for Maya. Now on page 120 of 240." At the last page it marks the book finished, as the app's Log pages sheet does. With Reading off: "Reading is turned off in Kinwall."
  - **Vote in a poll (Shortcuts action, built 2026-10-08):** **Poll** (the family's open polls, `GET /api/polls?status=open`), **Choice** (only that poll's choices, through `@IntentParameterDependency`) and **Who's voting**. A phone that belongs to someone (`GET /api/me`) votes for them, as the server requires; on a shared one, it asks "Who's voting?". `PUT /api/polls/{id}/vote`, then "Maya voted for Tacos in Friday dinner?". Voting again changes the vote. With Polls off: "Polls are turned off in Kinwall."
  - **Add an event (Shortcuts action, built 2026-10-08):** **Title**, **Starts** (a date and time), optional **Ends** (an hour later when left out) and **Calendar** (the calendars this phone can add to, the family's default for new events first, `GET /api/calendars` `default: true`). It uses the app's own sign-in when the phone has one (a grown-up's phone: every calendar), else the widgets' key (the calendars walls and kids may add to); with no calendar it can add to, it says to sign in as a grown-up. `POST /api/events`, then "Added Soccer practice to Family on Saturday, October 10, 3:00 PM."
  - **No Kinwall timer:** a "Start a Kinwall timer" action was considered and left out. Kinwall's timers belong to the device they're started on (kinwall's `docs/using/timers.md`): one started from Siri would never show on the wall or the Board, so it would only be a worse Clock timer.
  - Signed out, each says "Kinwall isn't signed in on this iPhone. Open Kinwall and sign in first."; in the demo they read the demo family (tacos for dinner) and save nothing; a refusal from the server (another person's book on a kid's device) is read out in its own words.

  - **Errors (fixed 2026-09-30):** an intent or entity query that couldn't reach the server used to crash the app: App Intents send a thrown error back over XPC, and a `URLError` carries the connection's `NWPath`, which XPC can't encode. Siri just failed, and the app also crashed at launch while Siri refreshed its list names. KinwallKit now throws `APIError.unreachable` ("Can't reach Kinwall right now.") instead, and a Keychain failure reads as one.

  They run in the app's process with the widgets' key; the ones that open the app hand their link to the web app through the native module (`PendingLink`), so one that launches the app isn't lost. In the demo they answer from the demo family and save nothing (and the adds say so). Checked in the iOS 26.5 Simulator (iPhone 17 Pro): What's on today, Mark a chore done (with its chore and person pickers) and Night screen. The earlier "Couldn't find AppShortcutsProvider" came from the Simulator build being signed ad hoc, with no team; `scripts/sign-simulator.sh` re-signs it (README).
- **Take now and Clock & next (built 2026-09-29):** Take now reads `GET /api/medications/due` with the widgets' key every 15 minutes; the Home Screen size has **Taken**, which marks the first dose (`MarkDoseIntent`). The medicines feature turned off (404) shows "Nothing due". Checked in the Simulator with the demo: both on the Home Screen, and Take now and Chores left on the Lock Screen.
- **Watch: Take now, transition warnings, meds complication (built 2026-09-29):**
  - **Take now** is a fourth page in the Watch app: the doses due now with **Taken** and **Snooze** (10 minutes), straight to the server with the Watch's key (`POST /api/medications/{id}/doses`). A person's own Watch shows their medicines' names, as the server allows; otherwise "Medicine".
  - **Transition warnings** (`targets/watch/Transitions.swift`): the Watch's person (picked on My chores) gets their transition reminders as local notifications, computed on the Watch from their next 24 hours of events (`KinwallKit TransitionWarnings`, the server's rule: before the leave-by time when they have leave-by on, else before the start). Rescheduled when the app opens and on background refresh about every 30 minutes. Limits: no push, so an event added elsewhere is only covered after the next refresh; watchOS keeps 64 pending notifications (48 used); in the background watchOS plays its own notification tap, and the distinct pattern (three rising taps) plays only while the app is frontmost; meal prep times aren't in the events API, so a meal counts from its start.
  - **Take now complication:** the count of doses due, never names.
  - Checked in the Simulator against a local Kinwall server with the demo family's names (a paired iPhone 17 and Watch, the phone paired as Maya's): the Watch got its own key (owner Maya), Today and My chores show her day, Check-in's one tap saved her sleep, Take now's Snooze took the dose off the due list, and a warning scheduled for 5 minutes before a new event of hers fired on time with the three-tap pattern (WatchKit logged the three haptics).
- **Daily check-in and Energy battery (built 2026-09-29), health data:** `targets/widgets/HealthWidgets.swift`.
  - **Whose:** the widgets' key is an everyday-access device key that inherits the owner of the app's sign-in (the pairing's or OAuth approval's "Who uses it"). When that owner is a person, it's their own device and the widgets work for them; the server allows exactly that (`GET/PUT /api/members/{id}/temp-check`, `GET /api/members/{id}/battery` accept a display key whose owner is the member). A shared key (owner `shared`, a wall or a parent's phone left on the whole family) shows "Only on a person's own device"; the on-device "Show only" filter isn't ownership. A parent's phone can't pick a kid: that would need the parent's admin key in the shared Keychain, and the widgets deliberately never get the app's rotating sign-in. A parent sets their own phone's "Who uses it" to themselves to get their own check-in.
  - **Daily check-in** (medium, interactive): morning "How did you sleep?" (five faces), then a few feelings (their own first), then "Goal for today?", which opens the app (a widget can't take typing; the web app opens the check-in once it reads `#/calendar?checkin=<member>`). In the evening, once their evening time has passed: "Did you finish your goal?" (Yes, Partly, Not today) and, with the battery on, "How drained do you feel?" (Full, OK, Low, Empty). Then a quiet "Checked in". Each tap goes straight to the server (`TempCheckAnswerIntent`) and reloads the battery. Nothing is kept beyond the entry on show.
  - **Energy battery:** small shows the level and word ("62% · Good by this evening"); medium adds the top two reasons and the heads-up for today or tomorrow. The Lock Screen (circular) is the gauge only, no reasons and no name, always: nothing to read over a shoulder, so it needs no opt-in. Off: "Turn on the Energy battery in Temp check settings." Refreshes every 3 hours and after a check-in answer. Text is privacy-sensitive, so a locked iPhone redacts it.
  - **Watch:** a Check-in page with a one-tap "How did you sleep?", and an Energy complication (gauge only), both with the Watch's own key, which inherits the iPhone sign-in's owner the same way.
  - In the demo, both show Maya's (the web demo's battery numbers); taps open the demo instead of saving. Checked in the Simulator with the demo: both in the widget gallery and on the Home Screen. Answering against a real server is build-only here (no paired family in the Simulator).
- **Spotlight (built 2026-09-29):** the family's recipes, lists and contacts, by name with a short line ("Recipe · 35 min · …", "Shopping list · 12 left", "Contact · Grandparent"), never notes, phone numbers, addresses or health entries. `src/spotlight.ts` fetches them with the widgets' key when the app opens or comes back (at most every 10 minutes) and hands them to `modules/kinwall-native/ios/Spotlight.swift`, which replaces the app's items; sign-out clears them. The demo shows a few of the demo family's. Each item's identifier is its app link, so a tap opens its page (`native/ios/AppHooks.swift`). The web app opens Lists on the list (`?list=`); a recipe or contact opens Meals or Contacts until it reads `?recipe=` and `?contact=`. Checked in the Simulator: "Rosa" finds Grandma Rosa and the tap opens Contacts.
- **Next:** install on a real iPhone and Watch; check Siri, reminder taps and complications there.

## Android

Built 2026-09-30. The Android side of the widgets, reminders and Controls above, on the same API and the widgets' own key.

### Notification channels

One channel per purpose (`modules/kinwall-native/android` `Channels.kt`), each tuned in Android **Settings → Apps → Kinwall → Notifications**. Channel ids are permanent, so the existing ones kept theirs:

| Channel | Id | Starts | What's on it |
|---|---|---|---|
| **Event reminders** | `reminders` (unchanged) | High | Event reminders, with **Snooze 10 min** and **Open** |
| **Leave-by** | `leave_by` (new) | High | The leave-by and start-prep countdowns, and "Leave by…" reminders. Off on a phone that had turned off the old countdowns channel, where they used to be |
| **Medicine** | `medicine` (new) | High | Medicine reminders (**Taken**, **Snooze 10 min**) and the due-dose countdown |
| **Chores** | `chores` (new) | Off | The chore nudge. Turning the channel on is the opt-in (iPhone uses Settings → Kinwall); it comes at 8:00 AM |
| **Timers and countdowns** | `countdowns` (unchanged) | Default | The cooking timer's countdown and the shopping trip |
| **Cooking timers** | `cooking_timers` (unchanged) | High, alarm sound | A timer that's up |

**Medicine through Do Not Disturb:** the Medicine channel's own **Override Do Not Disturb** switch, which the person sets; no `ACCESS_NOTIFICATION_POLICY`. The channel's description says so. The page can open that channel's settings: `window.kinwallNative.notificationSettings` is true on Android, and the message `{ type: 'notificationSettings', channel: 'medicine' }` opens `Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS` (any channel id above; without one, the app's notification settings). The web app doesn't send it yet (docs/PLAN.md, web changes).

Each countdown kind posts in a notification group of its own, so Android's auto-bundling (four or more of an app's notifications) can't fold it into a summary, which can't be promoted to a Live Update.

### Reminder buttons

The same categories as iPhone (`src/reminders.ts`), now on both platforms, with the same medicine reminders and chore nudge (`src/reminderPlans.ts`) on a person's own phone (the widgets' key's owner, `GET /api/me`). Medicine text stays generic ("Time for your medicine", "8:00 AM dose"). The buttons run in `ReminderActions.kt` without opening the app: expo-notifications sends its events to the app's highest-priority receiver for its action (its own has -1), so `ReminderActions`, a subclass of its `NotificationsService` at priority 0, gets them, handles Snooze, Taken and Done, and passes everything else on. Taken and Snooze are `POST /api/medications/{id}/doses` (the due-dose countdown for the same dose follows), Done is `POST /api/chores/{id}/complete`, with the widgets' key. A snooze is a copy 10 minutes later (`snz:…`); a Taken or Done that can't be saved comes straight back with "Didn't save. Try again, or open Kinwall." Open, and a tap, open the event as before.

### Widgets

Four, rendered from JavaScript (`src/widgets.tsx`, [`react-native-android-widget`](https://github.com/sAleksovski/react-native-android-widget) by Stefan Aleksovski), each with a picker preview (`assets/widgets/`) and description:

| Widget | Size | What it does |
|---|---|---|
| **Now & Next** (`Kinwall`) | 3×2 | As before: now, next with the leave-by time, chores left |
| **Chores** | 3×3 | Today's chores, ones left first. Its settings (touch and hold → the pencil) pick a person or Everyone; by default the phone's own person, else Everyone. A tap ticks it (`POST /api/chores/{id}/complete`); an Anyone chore credits the widget's person, or opens the app on "Who did it?" when it's set to Everyone; one with an open checklist opens that checklist. A chore waiting for a parent's OK (`pending`, from the widgets' key) shows ✅ with the done ones and isn't counted as left, as on iPhone, and a tap opens Chores instead of ticking it again; the chore nudge leaves it out too |
| **List** | 3×3 | Groceries (the family's default Groceries list, else the first Groceries-type list, else one named Groceries, else the first shopping list), or a list picked in its settings. Tap an item to tick it; **+ Add** opens the list in the app, where the add field is |
| **Take now** | 2×2 | How many medicines are due now (`GET /api/medications/due`). Never their names: a count and "Medicine" only |

- **Colors:** each widget draws a light and a dark version in the family's saved colors (`src/appearance.ts` `widgetPalette`: the page's surfaces with Kinwall's text and accent), so it follows Android's dark theme, or stays in the family's light or dark when they chose one. Kinwall's own colors before the page has sent any.
- **Offline or refused:** the widget says so ("Can't reach Kinwall right now", "Didn't save. Try again, or open Kinwall.") and the row stays.
- **Home Screen only:** the library declares every widget `widgetCategory="home_screen"`, never `keyguard`, so none can go on the Lock Screen or the Android 16 lock-screen hub. Take now above all.
- **Refresh:** every 30 minutes, after a tick (all of them), and when the app syncs (`reloadWidgets`, which sends Android's own update broadcast from `Widgets.kt`).
- **Demo:** the demo family's chores and Groceries; taps open the demo instead of ticking.

### Shortcuts and Quick Settings tiles

- **Launcher shortcuts** (touch and hold the icon; `res/xml/kinwall_shortcuts.xml`): **Add to Groceries**, **Start shopping**, **My chores**, **Night screen**. They open `family.kinwall.app:/open?to=groceries`, `?to=groceries/shop`, `?to=chores` and `?to=night`. A shortcut can't know the list's id, so the app looks up Groceries (the same pick as the List widget) with the widgets' key; signed out, offline or in the demo it opens Lists.
- **Quick Settings tiles** (`Tiles.kt`): **Add to Groceries** and **Night screen**, from the Quick Settings editor. On Android 13 and later the page can offer one: `window.kinwallNative.quickSettingsTiles` is true, and `{ type: 'addTile', tile: 'groceries' | 'night' }` asks Android (`requestAddTileService`), which shows its own prompt. Optional; the web app doesn't send it yet.

Checked on the Pixel emulator (Android 16): the channels are created (Chores off), the countdowns post on Leave-by and Timers and countdowns in their own groups and stay out of Android's auto-bundle, expo-notifications resolves `ReminderActions` ahead of its own receiver and scheduled reminders still arrive through it, the four widgets show in the picker with their previews and descriptions, the Chores widget shows the demo family and switches to the dark palette with the system's dark theme, the four shortcuts are registered, and the Groceries tile opens the app. To check on a phone with a real family: each reminder button with the app closed (and in airplane mode, to see a failed Taken come back), the chore nudge after turning on the Chores channel, ticking in the Chores and List widgets, the Override Do Not Disturb switch on Medicine, and the Live Update chip now that the countdowns are grouped.

## A sensible first pass

- **M3 (iPhone widgets):**
  - Now & Next and Today.
  - Interactive Chores and List widgets.
  - Next event and Chores left on the Lock Screen.
  - Local notifications for reminders and leave-by.
- **M4 (Watch):**
  - Today, My chores and Lists.
  - Next event and Chores left complications.
  - Haptic transition warnings.
- **M5 (Siri):**
  - Add to a list, What's next, and Complete a chore.
  - These double as the actions behind the interactive widgets.
