// What the Android widgets show and what a tap does (src/widgets.tsx draws them). No React Native
// imports, so test/widgetData.test.ts runs it under plain node.

import type { ChoreDay } from './reminderPlans'

/** Done or waiting for a parent's OK: either way it's ticked, and ticking it again does nothing new
 * (KinwallKit ChoreDay.isTicked). */
export const isTicked = (c: Pick<ChoreDay, 'completed' | 'pending'>) => c.completed || c.pending === true

/** `catalog`: a shopping list's type; missing from servers older than list types. */
export type FamilyList = { id: string; name: string; emoji?: string | null; kind: 'todo' | 'shopping' | 'reusable'; catalog?: 'groceries' | 'shopping' | null; isDefault?: boolean; archived: boolean; openCount: number }
export type ListItem = { id: string; title: string; quantity?: string | null; done: boolean }
export type ListDetail = { list: FamilyList; items: ListItem[] }

/** The list the List widget, the shortcuts and the tiles mean by default: the family's default
 * Groceries list (isDefault), else the first Groceries-type list, else one named Groceries, else the
 * first shopping list, else the first list (as the iOS controls and Siri pick it, KinwallKit
 * FamilyList.groceries). */
export function pickGroceries(lists: FamilyList[]): FamilyList | null {
  const open = lists.filter((l) => !l.archived)
  const groceries = (l: FamilyList) => l.kind === 'shopping' && l.catalog === 'groceries'
  return open.find((l) => groceries(l) && l.isDefault) ?? open.find(groceries) ?? open.find((l) => l.name.trim().toLowerCase() === 'groceries') ?? open.find((l) => l.kind === 'shopping') ?? open[0] ?? null
}

/** A Chores widget's rows: one person's (with Anyone chores), or everyone's; ones left first. */
export function choreRows(chores: ChoreDay[], person: string | null): ChoreDay[] {
  const mine = person ? chores.filter((c) => c.memberId === person || c.memberId == null) : chores
  return [...mine.filter((c) => !isTicked(c)), ...mine.filter(isTicked)]
}

/** A tap on a chore: tick it here, or open the app (a link's `to=`) where it needs more. An Anyone
 * chore is credited to the widget's person; with no person the app asks "Who did it?". One with an
 * open checklist opens that checklist; a done one (or one waiting for a parent's OK) opens Chores. */
export type ChoreTap = { tick: true; memberId: string | null } | { tick: false; open: string }
export function choreTap(c: ChoreDay, person: string | null): ChoreTap {
  if (isTicked(c)) return { tick: false, open: 'chores' }
  if ((c.checklist && c.checklist.done < c.checklist.total) || (c.memberId == null && !person)) return { tick: false, open: `chores&done=${c.id}` }
  return { tick: true, memberId: c.memberId == null ? person : null }
}

/** Medicines show only with medication reminders on and the Health tracker on (as the server
 * decides); a setting that's missing (older servers, offline) counts as on. */
export const medicinesOn = (s: { features?: Partial<Record<string, boolean>>; medications?: boolean }) =>
  s.medications !== false && s.features?.trackersHealth !== false

/** Take now says how many, never which: "Medicine" is all a Home Screen shows. */
export const takeNowText = (due: number) => (due === 0 ? 'Nothing due now' : `${due} due now`)

// ---- The demo family (while Try the demo is open, src/demo.ts), like the iOS widgets' own ----

export const DEMO_PEOPLE: Record<string, string> = { m3: 'Maya', m4: 'Leo' }
export const DEMO_CHORES: (ChoreDay & { emoji: string })[] = [
  { id: 'ch2', title: 'Feed the dog', emoji: '🐕', memberId: 'm3', completed: true },
  { id: 'ch7', title: 'Practice piano', emoji: '🎹', memberId: 'm3', completed: false },
  { id: 'ch6', title: 'Tidy toys', emoji: '🧸', memberId: 'm4', completed: false },
  { id: 'ch8', title: 'Take out the recycling', emoji: '♻️', memberId: 'm4', completed: false },
  { id: 'ch4', title: 'Water plants', emoji: '🪴', memberId: null, completed: false },
]
export const DEMO_GROCERIES: ListDetail = {
  list: { id: 'l1', name: 'Groceries', emoji: '🛒', kind: 'shopping', catalog: 'groceries', archived: false, openCount: 5 },
  items: [
    { id: 'li1', title: 'Milk', quantity: '1 gal', done: false },
    { id: 'li2', title: 'Eggs', quantity: '1 dozen', done: false },
    { id: 'li4', title: 'Apples', quantity: '6', done: false },
    { id: 'li5', title: 'Paper towels', done: false },
    { id: 'g1', title: 'Blueberries', quantity: '3 pints', done: false },
  ],
}
