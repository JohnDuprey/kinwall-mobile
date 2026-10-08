// node --test test/ (npm test). The Android widgets' rows and taps.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { type FamilyList, choreRows, choreTap, isTicked, medicinesOn, pickGroceries, takeNowText } from '../src/widgetData.ts'
import type { ChoreDay } from '../src/reminderPlans.ts'

const list = (id: string, name: string, kind: FamilyList['kind'], archived = false, catalog?: FamilyList['catalog']): FamilyList => ({ id, name, kind, catalog, archived, openCount: 0 })

test('pickGroceries: the Groceries type first, then the name, then any shopping list', () => {
  const household = list('h', 'Household', 'shopping', false, 'shopping'), food = list('f', 'Food', 'shopping', false, 'groceries')
  assert.equal(pickGroceries([list('g', 'Groceries', 'shopping', false, 'shopping'), household, food])?.id, 'f')
  assert.equal(pickGroceries([list('x', 'Old food', 'shopping', true, 'groceries'), household, list('g', 'Groceries', 'shopping')])?.id, 'g')
  assert.equal(pickGroceries([household, list('t', 'To-dos', 'todo')])?.id, 'h')
})

test("pickGroceries: the family's default Groceries list wins (server 0088 isDefault)", () => {
  const food = list('f', 'Food', 'shopping', false, 'groceries'), costco = { ...list('c', 'Costco', 'shopping', false, 'groceries'), isDefault: true }
  assert.equal(pickGroceries([food, costco])?.id, 'c')
  assert.equal(pickGroceries([food, { ...costco, archived: true }])?.id, 'f', 'an archived default is skipped')
  assert.equal(pickGroceries([food, { ...list('h', 'Hardware', 'shopping', false, 'shopping'), isDefault: true }])?.id, 'f', "the Shopping type's default isn't the groceries one")
})

test('pickGroceries: Groceries, else the first shopping list, else the first list', () => {
  assert.equal(pickGroceries([list('a', 'To-dos', 'todo'), list('b', 'Costco', 'shopping'), list('c', ' groceries ', 'shopping')])?.id, 'c')
  assert.equal(pickGroceries([list('a', 'To-dos', 'todo'), list('b', 'Costco', 'shopping')])?.id, 'b')
  assert.equal(pickGroceries([list('x', 'Groceries', 'shopping', true), list('a', 'To-dos', 'todo')])?.id, 'a')
  assert.equal(pickGroceries([]), null)
})

const chore = (id: string, memberId: string | null, extra: Partial<ChoreDay> = {}): ChoreDay => ({ id, title: id, memberId, completed: false, ...extra })

test('choreRows: one person with Anyone chores, or everyone; ones left first', () => {
  const all = [chore('done', 'm3', { completed: true }), chore('mine', 'm3'), chore('leo', 'm4'), chore('anyone', null)]
  assert.deepEqual(choreRows(all, 'm3').map((c) => c.id), ['mine', 'anyone', 'done'])
  assert.deepEqual(choreRows(all, null).map((c) => c.id), ['mine', 'leo', 'anyone', 'done'])
})

test('choreTap: ticks where it can, opens the app where it needs more', () => {
  assert.deepEqual(choreTap(chore('a', 'm3'), null), { tick: true, memberId: null })
  assert.deepEqual(choreTap(chore('a', null), 'm3'), { tick: true, memberId: 'm3' }) // Anyone, credited to the widget's person
  assert.deepEqual(choreTap(chore('a', null), null), { tick: false, open: 'chores&done=a' }) // Who did it?
  assert.deepEqual(choreTap(chore('a', 'm3', { checklist: { total: 3, done: 1 } }), 'm3'), { tick: false, open: 'chores&done=a' })
  assert.deepEqual(choreTap(chore('a', 'm3', { checklist: { total: 3, done: 3 } }), 'm3'), { tick: true, memberId: null })
  assert.deepEqual(choreTap(chore('a', 'm3', { completed: true }), 'm3'), { tick: false, open: 'chores' })
})

test("a chore waiting for a parent's OK counts as ticked: listed with the done ones, and a tap opens Chores", () => {
  const waiting = chore('waiting', 'm3', { pending: true })
  assert.equal(isTicked(waiting), true)
  assert.equal(isTicked(chore('a', 'm3')), false)
  assert.equal(isTicked(chore('a', 'm3', { completed: true })), true)
  assert.deepEqual(choreRows([waiting, chore('mine', 'm3')], 'm3').map((c) => c.id), ['mine', 'waiting'])
  assert.deepEqual(choreTap(waiting, 'm3'), { tick: false, open: 'chores' })
})

test('takeNowText: a count, never a name', () => {
  assert.equal(takeNowText(0), 'Nothing due now')
  assert.equal(takeNowText(2), '2 due now')
})

test('medicinesOn: medication reminders and the Health tracker both on; missing counts as on', () => {
  assert.equal(medicinesOn({}), true, 'an older server, or offline')
  assert.equal(medicinesOn({ medications: true, features: { chores: false } }), true)
  assert.equal(medicinesOn({ medications: false }), false)
  assert.equal(medicinesOn({ medications: true, features: { trackersHealth: false } }), false)
})
