// The app's own links (family.kinwall.app:/open?…) from widgets, Live Activities, reminders and
// shares, as the web app's route. No React Native imports, so test/links.test.ts runs it under node.

/** family.kinwall.app:/open?to=chores&done=abc → "chores?done=abc"; ?to=home (or an older widget's ?to=calendar) → Home; a trip's Live Activity, ?to=lists/<id>/shop → shopping mode
 * (Siri adds &store=); Siri and the Controls, ?to=lists&list=<id> and ?to=night; Spotlight,
 * ?to=meals&recipe=<id> and ?to=contacts&contact=<id>; a shared contact, ?to=contacts/import; what
 * the share sheet or Add to Kinwall added, ?to=shared&link=<Kinwall's link> (its #/ route, in
 * Calendar, Meals or the library: an event or a book to check, or what was added); anything else → null. */
export function routeFor(link: string, server?: string | null): string | null {
  if (server && /^https:\/\//.test(link)) {
    try {
      const u = new URL(link), own = new URL(server)
      if (u.origin !== own.origin || u.username || u.password || !u.hostname.endsWith('.kinwall.family')) return null
      if (u.pathname === '/open') return routeFor(`family.kinwall.app:/open?${u.searchParams}`, server)
      return u.pathname === '/' ? notificationRoute(link, server) : null
    } catch { return null }
  }
  const m = /^family\.kinwall\.app:\/*open\?(.*)$/.exec(link)
  if (!m) return null
  const q = new URLSearchParams(m[1])
  const to = q.get('to')?.replace(/^\//, '')
  // POST /api/share's link (targets/share, native/ios SiriIntents.swift AddToKinwallIntent, Android's
  // modules/kinwall-native ShareActivity.kt): only its
  // route, so it opens on this app's own server. WebShell sets it as location.hash, quoted.
  if (to === 'shared') {
    const route = /^https?:\/\/[^#\s]+#\/((?:calendar|meals|trackers\/library)(?:\?[^\s]*)?)$/i.exec(q.get('link') ?? '')?.[1]
    return route && route.length <= 2000 ? route : null
  }
  // A contact shared on Android (plugins/withKinwallNative.js): WebShell takes its vCard from the native module.
  if (to === 'contacts/import') return to
  // Ids land in page script, so only plain id characters pass.
  const id = (v: string | null) => (v && /^[A-Za-z0-9_-]+$/.test(v) ? v : null)
  // Shopping mode; Siri's "Start shopping at <store>" adds the store (the web app picks it up once
  // it reads ?store=; until then it asks, as it always has).
  if (to && /^lists\/[A-Za-z0-9_-]+\/shop$/.test(to)) {
    const store = q.get('store')?.trim()
    return store && store.length <= 100 ? `${to}?store=${encodeURIComponent(store)}` : to
  }
  // The check-in widget's "Goal for today?": their check-in on Home (the web app opens it once it reads #/home?checkin=).
  if (to === 'checkin') { const m = id(q.get('member')); return m ? `home?checkin=${m}` : 'home' }
  if (to === 'pair') return server ? pairingRoute(q) : null
  if (to === 'routine') return 'routine'
  if (to === 'night') return 'night' // the night screen (WebShell sends the 🌙 button's event)
  // Android's shortcuts and Quick Settings tiles, which can't know the list's id: App.tsx looks up
  // Groceries (groceriesRoute) before the page opens it.
  if (to === 'groceries' || to === 'groceries/shop') return to
  if (to === 'lists') { const l = id(q.get('list')); return l ? `lists?list=${l}` : 'lists' }
  // Spotlight: a recipe or a contact (src/spotlight.ts).
  if (to === 'meals') { const r = id(q.get('recipe')); return r ? `meals?recipe=${r}` : 'meals' }
  if (to === 'contacts') { const c = id(q.get('contact')); return c ? `contacts?contact=${c}` : 'contacts' }
  // Home (Board/Newscast). Widgets and Live Activities from before Home and Calendar split still say
  // to=calendar and mean Home; events and drafts open in Calendar through to=shared or a reminder's route.
  if (to === 'home' || to === 'calendar') return 'home'
  if (to !== 'chores') return null
  const done = id(q.get('done'))
  return done ? `chores?done=${done}` : to
}

/** Server notification links can only open an app page on the current family's origin. */
export function notificationRoute(link: string, server: string, source?: string): string | null {
  if (link.length > 4000 || /[\\\u0000-\u001f]/.test(link) || link.startsWith('//')) return null
  try {
    const u = new URL(link, server), own = new URL(server)
    if (source && new URL(source).origin !== own.origin) return null
    if (u.origin !== own.origin || u.username || u.password) return null
    const route = u.hash.startsWith('#/') ? u.hash.slice(2) : u.pathname.slice(1) + u.search
    if (!route) return 'home'
    if (route.startsWith('pair?')) return pairingRoute(new URLSearchParams(route.slice(5)))
    return /^(?:home|calendar|chores|lists|meals|medications|contacts|trackers|settings|outings|rewards|polls|insights|newscast)(?:[/?]|$)/.test(route) ? route : null
  } catch { return null }
}

/** 'groceries' (add to it) or 'groceries/shop' (shopping mode) with the family's Groceries list
 * (src/widgetData.ts pickGroceries); Lists when there's none, or it can't be fetched. */
export function groceriesRoute(route: string, groceriesId: string | null | undefined): string {
  if (!groceriesId || !/^[A-Za-z0-9_-]+$/.test(groceriesId)) return 'lists'
  return route === 'groceries/shop' ? `lists/${groceriesId}/shop` : `lists?list=${groceriesId}`
}

/** Page script for a shared contact: opens Contacts and hands the vCard to the page's import review
 * (web/src/native.ts receiveSharedContacts), without photos (Kinwall ignores them, and they're most
 * of a card's size). Just opens Contacts when there's no vCard, or it's over the page's 2 MB. */
export function importContactsScript(vcard: string | null | undefined): string {
  const open = `location.hash = '#/contacts'; true;`
  // A photo, logo, sound or key property and its folded lines (those starting with a space or tab).
  const card = vcard?.replace(/^(PHOTO|LOGO|SOUND|KEY)[;:].*(\r?\n[ \t].*)*\r?\n/gim, '')
  if (!card || card.length > 2_000_000 || !/BEGIN:VCARD/i.test(card)) return open
  return `location.hash = '#/contacts'; window.dispatchEvent(new CustomEvent('kinwall:import-contacts', { detail: ${JSON.stringify(card)} })); true;`
}

/** The contact sheet's Video call on Android (web/src/Contacts.tsx meetHref in the kinwall repo):
 * `intent:tel:<number>#Intent;action=com.google.android.apps.tachyon.action.CALL;package=com.google.android.apps.tachyon;end`
 * → the number, for KinwallNative.videoCall. Any other intent: link (the page can't start other
 * apps' intents) → null. */
export function meetCall(url: string): string | null {
  const m = /^intent:tel:(\+?[0-9]{7,15})#Intent;action=com\.google\.android\.apps\.tachyon\.action\.CALL;package=com\.google\.android\.apps\.tachyon;end$/.exec(url)
  return m?.[1] ?? null
}

/** Opens approval only. The web screen still requires parent access and an explicit confirmation. */
function pairingRoute(query: URLSearchParams): string | null {
  const codes = query.getAll('code')
  const code = codes[0]
  return codes.length === 1 && code !== undefined && /^\d{6}$/.test(code) ? `pair?code=${code}` : null
}
