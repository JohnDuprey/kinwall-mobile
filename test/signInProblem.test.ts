import { test } from 'node:test'
import assert from 'node:assert/strict'
const OAuthError = class extends Error { code: string; constructor(code: string, m: string) { super(m); this.code = code } }
import { signInProblem } from '../src/signInProblem.ts'

test('sign-in problems are plain sentences', () => {
  assert.match(signInProblem(new TypeError('Network request failed'), 'k.example.com'), /^Couldn't reach k\.example\.com\./)
  assert.match(signInProblem(new OAuthError('http_500', 'HTTP 500'), 'k.example.com'), /had a problem/)
  assert.equal(signInProblem(new OAuthError('access_denied', 'Sign-in was declined.'), 'h'), 'Sign-in was declined.')
})
