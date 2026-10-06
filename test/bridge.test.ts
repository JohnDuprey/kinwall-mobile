// node --test test/ (npm test). Which pages the app trusts: its own server's origin, and bridge
// messages that carry this launch's nonce.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { bridgeMessage, sameDocument, sameOrigin } from '../src/bridge.ts'

const server = 'https://sam.kinwall.family'

test('sameOrigin: scheme, host and port all have to match', () => {
  assert.equal(sameOrigin('https://sam.kinwall.family/#/chores', server), true)
  assert.equal(sameOrigin('http://sam.kinwall.family/', server), false) // a downgrade never gets the key
  assert.equal(sameOrigin('https://sam.kinwall.family:8443/', server), false)
  assert.equal(sameOrigin('https://evil.example/', server), false)
  assert.equal(sameOrigin('not a url', server), false)
  assert.equal(sameOrigin('http://192.168.1.5:8787/x', 'http://192.168.1.5:8787'), true)
})

test('bridgeMessage: needs the nonce, from a Kinwall page that is not a plugin', () => {
  const ok = JSON.stringify({ type: 'signedIn', nonce: 'n1' })
  assert.deepEqual(bridgeMessage(ok, 'n1', `${server}/#/`, server), { type: 'signedIn', nonce: 'n1' })
  assert.equal(bridgeMessage(JSON.stringify({ type: 'signedIn' }), 'n1', `${server}/`, server), null) // another frame: no nonce
  assert.equal(bridgeMessage(JSON.stringify({ type: 'signedIn', nonce: 'n2' }), 'n1', `${server}/`, server), null)
  assert.equal(bridgeMessage(ok, 'n1', `${server}/plugins/x/index.html`, server), null)
  assert.equal(bridgeMessage(ok, 'n1', 'http://sam.kinwall.family/', server), null)
  assert.equal(bridgeMessage('{', 'n1', `${server}/`, server), null)
  assert.equal(bridgeMessage('null', 'n1', `${server}/`, server), null)
})

test('sameDocument: only a #/ route change on the same page', () => {
  assert.equal(sameDocument(`${server}/#/today`, `${server}/#/chores`), true)
  assert.equal(sameDocument(`${server}/`, `${server}/#/chores`), true)
  assert.equal(sameDocument(`${server}/#/today`, `${server}/#/today`), false) // a reload
  assert.equal(sameDocument(null, `${server}/#/today`), false) // the first load
  assert.equal(sameDocument(`${server}/?start=pair`, `${server}/#/today`), false)
  assert.equal(sameDocument(`${server}/#/today`, `${server}/auth/callback?code=x`), false)
})
