// node --test test/ (npm test). The app's family.kinwall.app:/open links: widgets, Live Activities, shares.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { groceriesRoute, routeFor, importContactsScript, meetCall, notificationRoute } from '../src/links.ts'

test('server notifications: every notification destination opens with its selection intact', () => {
  const server = 'https://our-family.kinwall.family'
  // Destinations emitted by notify.ts, milestones.ts and the notification-producing routes.
  const routes = [
    'journal/m3', 'home?checkin=m3&checkinPart=morning',
    'upkeep?thing=thing-1', 'upkeep?job=job-1',
    'calendar?event=e1&at=2026-10-23T18%3A00%3A00Z', 'chores',
    'lists?list=l1', 'meals?meal=meal-1&orders=1', 'medications/m3',
    'insights/m3', 'trackers/library', 'outings?outing=o1', 'rewards/m3',
    'home?poll=p1', 'settings?tab=calendars&section=todo-apps',
    'settings?tab=access&section=security-activity',
  ]
  for (const route of routes) {
    assert.equal(notificationRoute(`/#/${route}`, server, server), route)
    assert.equal(notificationRoute(`${server}/#/${route}`, server, server), route)
    assert.equal(routeFor(`${server}/#/${route}`, server), route)
    assert.equal(notificationRoute(`/#/${route}`, server, 'https://other.kinwall.family'), null)
  }
  for (const route of ['journalism/m3', 'upkeeper', 'api/keys', 'oauth/callback']) {
    assert.equal(notificationRoute(`/#/${route}`, server), null)
  }
})

test('hosted links: only routes on this signed-in family open; other families and sign-in callbacks stay outside', () => {
  const server = 'https://our-family.kinwall.family'
  assert.equal(routeFor(`${server}/#/lists?list=l1`, server), 'lists?list=l1')
  assert.equal(routeFor(`${server}/open?to=chores&done=c1`, server), 'chores?done=c1')
  for (const u of ['https://other.kinwall.family/#/lists', `${server}/oauth/callback?code=x`, `${server}/#/api/keys`, `http://our-family.kinwall.family/#/home`, 'https://evil.invalid/#/home']) assert.equal(routeFor(u, server), null, u)
  assert.equal(notificationRoute('/#/medications/sam', server), 'medications/sam')
  assert.equal(notificationRoute('/chores', server), 'chores')
  assert.equal(notificationRoute('//evil.invalid/#/home', server), null)
  assert.equal(notificationRoute('/api/keys', server), null)
  assert.equal(notificationRoute('/#/lists', server, 'https://other.kinwall.family'), null, 'an old family notification cannot route into a new family')
})

test('routeFor: tabs and a chore to tick', () => {
  assert.equal(routeFor('family.kinwall.app:/open?to=home'), 'home')
  assert.equal(routeFor('family.kinwall.app:/open?to=calendar'), 'home', 'widgets from before Home and Calendar split meant Home')
  assert.equal(routeFor('family.kinwall.app:/open?to=calendar&event=e1'), 'home')
  assert.equal(routeFor('family.kinwall.app:/open?to=chores&done=c1'), 'chores?done=c1')
  assert.equal(routeFor('family.kinwall.app:/open?to=recipes/import&url=https%3A%2F%2Fexample.org%2Ftacos'), null, 'Android shares go to /api/share now')
  assert.equal(routeFor('family.kinwall.app:/open?to=settings'), null)
  assert.equal(routeFor('https://example.org'), null)
})

test('routeFor: a shopping trip\'s Live Activity opens its list in shopping mode', () => {
  assert.equal(routeFor('family.kinwall.app:/open?to=lists/l-1_a/shop'), 'lists/l-1_a/shop')
  assert.equal(routeFor('family.kinwall.app:/open?to=lists/x\'%3Balert(1)/shop'), null, 'only plain id characters reach page script')
})

test('routeFor: Siri and the Controls open shopping mode at a store, a list, the night screen', () => {
  assert.equal(routeFor('family.kinwall.app:/open?to=lists/l1/shop&store=Shaw%27s%20%26%20Co'), 'lists/l1/shop?store=Shaw\'s%20%26%20Co')
  assert.equal(routeFor('family.kinwall.app:/open?to=lists&list=l1'), 'lists?list=l1')
  assert.equal(routeFor('family.kinwall.app:/open?to=lists&list=x%27)'), 'lists', 'only plain ids reach page script')
  assert.equal(routeFor('family.kinwall.app:/open?to=night'), 'night')
})

test('routeFor: Spotlight opens a recipe, a list or a contact', () => {
  assert.equal(routeFor('family.kinwall.app:/open?to=meals&recipe=r-1'), 'meals?recipe=r-1')
  assert.equal(routeFor('family.kinwall.app:/open?to=contacts&contact=c_2'), 'contacts?contact=c_2')
  assert.equal(routeFor('family.kinwall.app:/open?to=contacts'), 'contacts')
  assert.equal(routeFor('family.kinwall.app:/open?to=meals&recipe=%3Cx%3E'), 'meals')
})

test('routeFor: the check-in widget opens that person\'s check-in', () => {
  assert.equal(routeFor('family.kinwall.app:/open?to=checkin&member=m3'), 'home?checkin=m3')
  assert.equal(routeFor('family.kinwall.app:/open?to=checkin&member=%3C'), 'home')
})

test('Android shortcuts and tiles: Groceries, found by the app', () => {
  assert.equal(routeFor('family.kinwall.app:/open?to=groceries'), 'groceries')
  assert.equal(routeFor('family.kinwall.app:/open?to=groceries/shop'), 'groceries/shop')
  assert.equal(groceriesRoute('groceries', 'l1'), 'lists?list=l1')
  assert.equal(groceriesRoute('groceries/shop', 'l1'), 'lists/l1/shop')
  assert.equal(groceriesRoute('groceries', null), 'lists')
  assert.equal(groceriesRoute('groceries/shop', "x')"), 'lists')
})

test('routeFor: a contact shared on Android opens the page\'s contact import', () => {
  assert.equal(routeFor('family.kinwall.app:/open?to=contacts%2Fimport'), 'contacts/import')
})

test('importContactsScript: hands the vCard to the page without its photo, or just opens Contacts', () => {
  const card = 'BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Ms. Park\r\nPHOTO;ENCODING=b;TYPE=JPEG:AAAA\r\n BBBB\r\n CCCC\r\nTEL:555-010-1234\r\nEND:VCARD'
  const script = importContactsScript(card)
  const m = /detail: ("(?:[^"\\]|\\.)*") \}/.exec(script)
  assert.ok(m, script)
  assert.equal(JSON.parse(m[1]), 'BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Ms. Park\r\nTEL:555-010-1234\r\nEND:VCARD')
  assert.match(script, /kinwall:import-contacts/)
  assert.match(script, /location\.hash = '#\/contacts'/)
  for (const nothing of [null, undefined, 'hello', 'BEGIN:VCARD\n' + 'x'.repeat(2_000_001)]) {
    assert.equal(importContactsScript(nothing), `location.hash = '#/contacts'; true;`)
  }
})

test('meetCall: the contact sheet\'s Video call link, and nothing else', () => {
  const meet = (to: string) => `intent:tel:${to}#Intent;action=com.google.android.apps.tachyon.action.CALL;package=com.google.android.apps.tachyon;end`
  assert.equal(meetCall(meet('+15555550123')), '+15555550123')
  assert.equal(meetCall(meet('5555550123')), '5555550123')
  assert.equal(meetCall(meet('123')), null, 'too short for a phone number')
  assert.equal(meetCall(meet('+1555;S.x=y')), null)
  assert.equal(meetCall('intent:tel:+15555550123#Intent;action=android.intent.action.CALL;end'), null, 'only Meet\'s call')
  assert.equal(meetCall('intent:#Intent;action=com.google.android.apps.tachyon.action.CALL;package=com.google.android.apps.tachyon;component=x/y;end'), null)
  assert.equal(meetCall('tel:+15555550123'), null)
})

test('routeFor: what the share sheet or Add to Kinwall added opens at its route', () => {
  // KinwallKit Share.appLink's and Android's Share.appLink's encoding (ShareTests.swift, ShareTest.kt): + stays a plus.
  assert.equal(routeFor('family.kinwall.app:/open?to=shared&link=https://k.example/%23/calendar?draft%3Devent%26title%3DSpring%2Bfair%26date%3D2026-05-09'), 'calendar?draft=event&title=Spring+fair&date=2026-05-09')
  assert.equal(routeFor(`family.kinwall.app:/open?to=shared&link=${encodeURIComponent('https://k.example/#/trackers/library?add=Wool&author=Hugh+Howey')}`), 'trackers/library?add=Wool&author=Hugh+Howey')
  assert.equal(routeFor(`family.kinwall.app:/open?to=shared&link=${encodeURIComponent('https://k.example/#/meals?restaurant=r1')}`), 'meals?restaurant=r1')
  assert.equal(routeFor(`family.kinwall.app:/open?to=shared&link=${encodeURIComponent('https://k.example/#/settings')}`), null, 'only the share routes')
  assert.equal(routeFor(`family.kinwall.app:/open?to=shared&link=${encodeURIComponent('javascript:alert(1)//#/calendar')}`), null)
  assert.equal(routeFor('family.kinwall.app:/open?to=shared'), null)
})

test('routine mode: opens only its own route', () => {
  assert.equal(routeFor('family.kinwall.app:/open?to=routine'), 'routine')
  assert.equal(routeFor('family.kinwall.app:/open?to=routine%2F..%2Fsettings'), null)
})

test('pairing approval: opens the current family’s six-digit QR code without approving it', () => {
  const server = 'https://our-family.kinwall.family'
  assert.equal(routeFor(`${server}/#/pair?code=123456`, server), 'pair?code=123456')
  assert.equal(routeFor('family.kinwall.app:/open?to=pair&code=123456', server), 'pair?code=123456')
  for (const code of ['12345', '1234567', 'ABCDEF', '123456&owner=maya', '123456#x']) {
    assert.equal(routeFor(`${server}/#/pair?code=${encodeURIComponent(code)}`, server), null, code)
  }
  assert.equal(routeFor('https://other.kinwall.family/#/pair?code=123456', server), null)
  assert.equal(routeFor(`${server}/#/pair?code=123456&owner=maya`, server), 'pair?code=123456')
  assert.equal(routeFor(`${server}/#/pair?code=123456&code=654321`, server), null)
  assert.equal(routeFor(`${server}/#/pair?code=123456?extra`, server), null)
  assert.equal(routeFor(`${server}/open?to=pair&code=123456`, server), 'pair?code=123456')
  assert.equal(routeFor('family.kinwall.app:/open?to=pair&code=123456'), null)
})
