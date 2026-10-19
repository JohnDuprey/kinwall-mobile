import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'

// Exercise the real release script with fake tools: never sign or upload a build in tests.
for (const failAt of ['archive', '-exportArchive', 'none']) {
  test(`TestFlight script: ${failAt === 'none' ? 'reports a successful export' : `stops when ${failAt} fails`}`, () => {
    const dir = mkdtempSync(join(tmpdir(), 'kinwall-testflight-test-'))
    try {
      for (const tool of ['npm', 'npx']) writeFileSync(join(dir, tool), '#!/bin/sh\nexit 0\n', { mode: 0o755 })
      writeFileSync(join(dir, 'xcodebuild'), '#!/bin/sh\necho "$1" >> "$CALLS"\n[ "$1" != "$FAIL_AT" ] || exit 42\necho "Xcode finished"\n', { mode: 0o755 })
      const calls = join(dir, 'calls')
      const result = spawnSync('scripts/testflight.sh', [], {
        encoding: 'utf8',
        env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, TEAM: 'TESTTEAM', UPLOAD: '0', OUT: join(dir, 'out'), CALLS: calls, FAIL_AT: failAt },
      })
      const ran = existsSync(calls) ? readFileSync(calls, 'utf8').trim().split('\n') : []
      if (failAt === 'none') {
        assert.equal(result.status, 0, result.stderr)
        assert.deepEqual(ran, ['archive', '-exportArchive'])
        assert.match(result.stdout, /Build .*\/export/)
      } else {
        assert.notEqual(result.status, 0, 'a failed Xcode command must fail the script')
        assert.deepEqual(ran, failAt === 'archive' ? ['archive'] : ['archive', '-exportArchive'])
        assert.doesNotMatch(result.stdout, /Build .*\/export|uploaded; it shows/)
      }
    } finally { rmSync(dir, { recursive: true, force: true }) }
  })
}
