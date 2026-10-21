import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'

test('App Intent descriptions omit the reserved Apple name rejected by App Store validation', () => {
  let descriptions = 0
  for (const root of ['native/ios', 'targets']) {
    for (const relative of readdirSync(root, { recursive: true })) {
      if (typeof relative !== 'string' || !relative.endsWith('.swift')) continue
      const file = join(root, relative)
      const source = readFileSync(file, 'utf8')
      const pattern = /static\s+let\s+description(?:\s*:\s*IntentDescription\??)?\s*=\s*(?:IntentDescription\(\s*)?"((?:\\.|[^"\\])*)"/g
      for (const [, description] of source.matchAll(pattern)) {
        descriptions++
        assert.doesNotMatch(description!, /apple/i, `${file}: App Store rejects Apple in App Intent descriptions (ITMS-90626)`)
      }
    }
  }
  assert.ok(descriptions > 0, 'must check the native intent descriptions')
})
