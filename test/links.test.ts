// node --test test/ (npm test). The app's family.kinwall.app:/open links: widgets, Live Activities, shares.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { groceriesRoute, routeFor, importContactsScript, meetCall } from '../src/links.ts'

test('routeFor: tabs, a chore to tick, a recipe to import', () => {
  assert.equal(routeFor('family.kinwall.app:/open?to=calendar'), 'calendar')
  assert.equal(routeFor('family.kinwall.app:/open?to=chores&done=c1'), 'chores?done=c1')
  assert.equal(routeFor('family.kinwall.app:/open?to=recipes/import&url=https%3A%2F%2Fexample.org%2Ftacos'), 'recipes/import?url=https%3A%2F%2Fexample.org%2Ftacos')
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
  assert.equal(routeFor('family.kinwall.app:/open?to=checkin&member=m3'), 'calendar?checkin=m3')
  assert.equal(routeFor('family.kinwall.app:/open?to=checkin&member=%3C'), 'calendar')
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
  // KinwallKit Share.appLink's encoding (ShareTests.swift): + stays a plus.
  assert.equal(routeFor('family.kinwall.app:/open?to=shared&link=https://k.example/%23/calendar?draft%3Devent%26title%3DSpring%2Bfair%26date%3D2026-05-09'), 'calendar?draft=event&title=Spring+fair&date=2026-05-09')
  assert.equal(routeFor(`family.kinwall.app:/open?to=shared&link=${encodeURIComponent('https://k.example/#/trackers/library?add=Wool&author=Hugh+Howey')}`), 'trackers/library?add=Wool&author=Hugh+Howey')
  assert.equal(routeFor(`family.kinwall.app:/open?to=shared&link=${encodeURIComponent('https://k.example/#/meals?restaurant=r1')}`), 'meals?restaurant=r1')
  assert.equal(routeFor(`family.kinwall.app:/open?to=shared&link=${encodeURIComponent('https://k.example/#/settings')}`), null, 'only the share routes')
  assert.equal(routeFor(`family.kinwall.app:/open?to=shared&link=${encodeURIComponent('javascript:alert(1)//#/calendar')}`), null)
  assert.equal(routeFor('family.kinwall.app:/open?to=shared'), null)
})
