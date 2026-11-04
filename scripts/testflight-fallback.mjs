// TestFlight's Linux controller. It has an Actions token, never Apple signing secrets.
import { pathToFileURL } from 'node:url'
import { setTimeout as delay } from 'node:timers/promises'

const WORKER = 'testflight-worker.yml'
const pause = ms => new Promise(resolve => setTimeout(resolve, ms))
const started = job => !!job && (!!job.runner_name || job.status === 'in_progress' || job.steps?.some(s => s.status === 'in_progress' || s.status === 'completed'))
const capacityMessage = /job was not acquired by Runner of type hosted/i

export function createGitHub({ repository, token, fetch: request = globalThis.fetch }) {
  if (!/^[\w.-]+\/[\w.-]+$/.test(repository) || !token) throw Error('A repository and Actions token are required')
  const base = `https://api.github.com/repos/${repository}`
  async function api(path, method = 'GET', body) {
    const response = await request(base + path, {
      method, headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2026-03-10' },
      ...(body ? { body: JSON.stringify(body), headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2026-03-10', 'Content-Type': 'application/json' } } : {}),
      signal: AbortSignal.timeout(30000),
    })
    if (method === 'POST' && path.endsWith('/cancel') && response.status === 409) return false
    if (!response.ok) throw Error(`GitHub ${method} ${path.split('?')[0]} returned ${response.status}`)
    if (response.status === 204) return null
    const text = await response.text()
    return text ? JSON.parse(text) : null
  }
  async function list(path, field) {
    const all = []
    for (let page = 1; page <= 10; page++) {
      const data = await api(`${path}${path.includes('?') ? '&' : '?'}per_page=100&page=${page}`)
      const rows = field ? data[field] : data
      if (!Array.isArray(rows)) throw Error('Unexpected GitHub list response')
      all.push(...rows)
      if (rows.length < 100) return all
    }
    throw Error('GitHub list exceeded the safe search limit; refusing to start another upload')
  }
  async function find(requestId, createdAt) {
    const query = new URLSearchParams({ event: 'workflow_dispatch', created: `>=${createdAt}` })
    const runs = await list(`/actions/workflows/${WORKER}/runs?${query}`, 'workflow_runs')
    const matches = runs.filter(r => r.display_title === `TestFlight build ${requestId}` && r.event === 'workflow_dispatch')
    if (matches.length > 1) throw Error('Multiple worker attempts have the same identity; refusing another upload')
    return matches[0]
  }
  return {
    run: id => api(`/actions/runs/${id}`),
    jobs: id => list(`/actions/runs/${id}/jobs?filter=latest`, 'jobs'),
    annotations: id => list(`/check-runs/${id}/annotations`),
    resolve: async ref => (await api(`/commits/${encodeURIComponent(ref)}`)).sha,
    cancel: async id => (await api(`/actions/runs/${id}/cancel`, 'POST')) !== false,
    find,
    async start({ ref, sourceSha, tag, runner, parentId, request: requestId, createdAt }) {
      // Rerunning the controller resumes its exact child, including a completed upload.
      const existing = await find(requestId, createdAt)
      if (existing) return existing.id
      const result = await api(`/actions/workflows/${WORKER}/dispatches`, 'POST', {
        ref, inputs: { source_sha: sourceSha, tag, runner, parent_id: String(parentId), request: requestId },
      })
      if (Number.isSafeInteger(result?.workflow_run_id)) return result.workflow_run_id
      // Older dispatch APIs return 204. Never repeat a dispatch with an ambiguous response.
      for (let attempt = 0; attempt < 12; attempt++) {
        const child = await find(requestId, createdAt)
        if (child) return child.id
        await pause(5000)
      }
      throw Error('Worker dispatch was accepted but its run could not be identified; do not dispatch a duplicate')
    },
  }
}

export async function orchestrate({ api, parentId, ref, sourceSha, tag = '', selection = 'auto',
  now = Date.now, sleep = pause, log = console.log, cancelled = () => false,
  queueMs = 180000, cancelMs = 120000, pollMs = 10000, runningPollMs = 30000 }) {
  if (!['auto', 'arm', 'intel'].includes(selection)) throw Error('Runner must be auto, arm, or intel')
  const parent = await api.run(parentId)
  const pinned = await api.resolve(tag || sourceSha)
  if (!/^[a-f0-9]{40}$/i.test(pinned)) throw Error('Could not pin the app source commit')
  let active
  const stop = async id => {
    const accepted = await api.cancel(id)
    const deadline = now() + cancelMs
    while (now() <= deadline) {
      const run = await api.run(id)
      if (run.status === 'completed') return { run, accepted }
      await sleep(pollMs)
    }
    throw Error('ARM cancellation could not be confirmed; refusing an Intel upload')
  }
  try {
    // An earlier controller attempt may already have completed the ARM-to-Intel handoff.
    const resumedIntel = selection === 'auto' && api.find
      ? await api.find(`${parentId}-intel`, parent.created_at) : null
    for (const runner of selection === 'auto' ? resumedIntel ? ['intel'] : ['arm', 'intel'] : [selection]) {
      if (cancelled()) throw Error('Controller cancelled')
      const id = await api.start({ ref, sourceSha: pinned, tag, runner, parentId,
        request: `${parentId}-${runner}`, createdAt: parent.created_at })
      active = id
      log(`TestFlight ${runner}: https://github.com/${process.env.GITHUB_REPOSITORY ?? 'repository'}/actions/runs/${id}`)
      let acquired = false, queuedAt = null, fallback = false
      for (;;) {
        if (cancelled()) throw Error('Controller cancelled')
        const run = await api.run(id)
        const jobs = !acquired || run.status === 'completed' ? await api.jobs(id) : []
        const job = jobs.find(j => j.name === 'upload')
        acquired ||= started(job)
        if (run.status === 'completed') {
          active = null
          if (run.conclusion === 'success') return id
          const capacity = !acquired && job && ['cancelled', 'failure'].includes(job.conclusion)
            && (await api.annotations(job.id)).some(a => capacityMessage.test(a.message))
          if (selection === 'auto' && runner === 'arm' && capacity) { fallback = true; break }
          throw Error(`TestFlight ${runner} ended with ${run.conclusion}; inspect run ${id}`)
        }
        if (selection === 'auto' && runner === 'arm' && !acquired && job?.status === 'queued') {
          queuedAt ??= now()
          if (now() - queuedAt >= queueMs) {
            // Recheck immediately before cancellation: an acquired runner gets to finish.
            const latest = (await api.jobs(id)).find(j => j.name === 'upload')
            if (started(latest)) { acquired = true; continue }
            if (latest?.status !== 'queued') { await sleep(pollMs); continue }
            const stopped = await stop(id)
            active = null
            if (stopped.run.conclusion === 'success') return id
            if (!stopped.accepted || stopped.run.conclusion !== 'cancelled') {
              throw Error(`ARM cancellation ended with ${stopped.run.conclusion}; refusing an Intel upload`)
            }
            fallback = true
            break
          }
        } else if (!acquired) {
          queuedAt = null // Environment approvals and other waits are not runner queue time.
        }
        await sleep(acquired ? runningPollMs : pollMs)
      }
      if (!fallback) throw Error('Unexpected TestFlight selection state')
      log('ARM runner unavailable; its attempt has stopped. Starting Intel with the same source commit.')
    }
    throw Error('No TestFlight worker completed')
  } catch (error) {
    // An API/controller error must not leave a detached worker uploading later.
    if (active != null) {
      try { if ((await api.run(active)).status !== 'completed') await api.cancel(active) } catch { /* The worker also checks the parent before archive and upload. */ }
    }
    throw error
  }
}

async function main() {
  const parentId = process.env.GITHUB_RUN_ID
  if (!/^\d+$/.test(parentId ?? '')) throw Error('Run this controller in GitHub Actions')
  const api = createGitHub({ repository: process.env.GITHUB_REPOSITORY, token: process.env.GH_TOKEN })
  if (process.argv.includes('--cancel')) {
    const parent = await api.run(parentId)
    for (const runner of ['arm', 'intel']) {
      const child = await api.find(`${parentId}-${runner}`, parent.created_at)
      if (child && child.status !== 'completed') await api.cancel(child.id)
    }
    return
  }
  const cancellation = new AbortController()
  process.on('SIGINT', () => cancellation.abort())
  process.on('SIGTERM', () => cancellation.abort())
  await orchestrate({ api, parentId, ref: process.env.GITHUB_REF_NAME, sourceSha: process.env.GITHUB_SHA,
    tag: process.env.RELEASE_TAG ?? '', selection: process.env.RUNNER_SELECTION ?? 'auto', cancelled: () => cancellation.signal.aborted,
    sleep: ms => delay(ms, undefined, { signal: cancellation.signal }).catch(error => { if (error.name !== 'AbortError') throw error }) })
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1 })
}
