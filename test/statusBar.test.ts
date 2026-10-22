import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readStatusBarHidden, saveStatusBarHidden, statusBarMessage, statusBarScript, statusBarSurface } from '../src/statusBar.ts'
import { parseAppearance } from '../src/appearance.ts'

test('status bar: validated accent surfaces survive storage and choose contrasting icons', () => {
  const colors = { light: { bg: '#ffffff', card: '#ffffff' }, dark: { bg: '#000000', card: '#000000' } }
  const input = { mode: 'auto', dark: false, colors, statusBarColors: { light: '#123857', dark: '#ffff00' } }
  const saved = parseAppearance(JSON.stringify(input))!
  assert.deepEqual(saved, input)
  assert.deepEqual(statusBarSurface(saved, false, '#ffffff'), { color: '#123857', style: 'light' })
  assert.deepEqual(statusBarSurface(saved, true, '#ffffff'), { color: '#ffff00', style: 'dark' })
  // The web's filled yellow accent: both inks are readable, black has the higher contrast.
  assert.deepEqual(statusBarSurface({ ...saved, mode: 'light', statusBarColors: { light: '#7a7a00', dark: '#7a7a00' } }, false, '#ffffff'), { color: '#7a7a00', style: 'dark' })
  assert.deepEqual(statusBarSurface({ ...saved, mode: 'dark', dark: true }, false, '#ffffff'), { color: '#ffff00', style: 'dark' })
  assert.deepEqual(statusBarSurface({ ...saved, mode: 'scheduled', dark: false }, true, '#ffffff'), { color: '#123857', style: 'light' })
  assert.deepEqual(statusBarSurface(null, false, '#050403'), { color: '#050403', style: 'light' })
  assert.deepEqual(statusBarSurface(parseAppearance({ mode: 'light', dark: false, colors }), true, '#ffffff'), { color: '#ffffff', style: 'dark' })
  assert.equal(parseAppearance({ ...input, statusBarColors: { light: 'red', dark: '#ffffff' } }), null)
  assert.equal(parseAppearance({ ...input, statusBarColors: { light: '#ffffff' } }), null)
})

test('status bar: visible by default on both platforms, including missing or damaged storage', () => {
  for (const value of [null, '', 'yes', 'null', '{}']) {
    const storage = { getItem: () => value }
    assert.equal(readStatusBarHidden(storage), false)
  }
  const blocked = { getItem: () => { throw Error('blocked') } }
  assert.equal(readStatusBarHidden(blocked), false)
})

test('status bar: save and restore both choices across launches on either platform', () => {
  const values = new Map<string, string>()
  const storage = { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => { values.set(key, value) } }
  for (const hidden of [false, true, false]) {
    assert.equal(saveStatusBarHidden(storage, hidden), true)
    assert.equal(readStatusBarHidden(storage), hidden)
  }
  assert.equal(saveStatusBarHidden({ setItem: () => { throw Error('blocked') } }, true), false)
})

test('status bar: accept only a boolean in the visibility message', () => {
  assert.equal(statusBarMessage({ type: 'statusBar', hidden: true }), true)
  assert.equal(statusBarMessage({ type: 'statusBar', hidden: false }), false)
  for (const value of [null, {}, { hidden: true }, { type: 'theme', hidden: true }, { type: 'statusBar', hidden: 'false' }, { type: 'statusBar', hidden: 0 }]) {
    assert.equal(statusBarMessage(value), null)
  }
})

test('status bar: the acknowledgement updates the page and announces either state', () => {
  for (const hidden of [true, false]) {
    const events: string[] = []
    const window = { kinwallNative: { statusBarHidden: !hidden }, dispatchEvent: (e: Event) => events.push(e.type) }
    Function('window', statusBarScript(hidden))(window)
    assert.equal(window.kinwallNative.statusBarHidden, hidden)
    assert.deepEqual(events, ['kinwallnative'])
  }
})
