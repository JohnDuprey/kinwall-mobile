import KinwallNative from '../modules/kinwall-native'
import { api, me, type Connection } from './api'
import { routineDecision, type RoutineDecision } from './routineMode'
let connection: Connection | null = null
let preview = false
let inFlight: Promise<unknown> | null = null
export function setRoutineConnection(next: Connection | null, demo = false) { connection = next; preview = demo }
/** On hardware, decisions always come from the authenticated server, never a web bridge payload. */
export async function syncRoutine(memberId?: string, sample?: unknown): Promise<unknown> {
  if (!KinwallNative?.routineStatus || !KinwallNative.routineApply) return null
  const status = await KinwallNative.routineStatus()
  if (status.simulator && preview) {
    const decision = routineDecision(sample)
    if (decision) return KinwallNative.routineApply(JSON.stringify(decision))
    return status
  }
  if (!connection) return status
  const c = connection
  const identity = await me(c)
  // A parent's screen may preview another child's routine but must never restrict their own phone.
  if (identity.scope !== 'display' || !identity.owner || identity.owner === 'shared') return status
  const bound = status.memberId
  if (bound && bound !== identity.owner) throw new Error('This device was set up for a different child. A grown-up must set it up again.')
  if (memberId && identity.owner !== memberId) throw new Error('This device can only check its own routine.')
  const state = await api<RoutineDecision>(c.baseURL, c.key, 'GET', `api/routine-mode/${encodeURIComponent(identity.owner)}`)
  const decision = routineDecision(state)
  if (!decision) throw new Error('The routine decision is out of date. Try again.')
  if (connection !== c) return status // account changed during the request
  return KinwallNative.routineApply(JSON.stringify({ ...decision, kinwallHost: new URL(c.baseURL).hostname }))
}
export function refreshRoutine() {
  inFlight ??= syncRoutine().catch(() => null).finally(() => { inFlight = null })
  return inFlight
}
export async function setupRoutine(memberId: string) {
  if (!KinwallNative?.routineSetup || !KinwallNative.routineStatus) throw new Error('Update the Kinwall app to set up routine mode.')
  const status = await KinwallNative.routineStatus()
  if (status.simulator && preview) return KinwallNative.routineSetup(memberId, status.appMode ?? 'selected', status.allowedWebsitesOnly ?? false)
  if (!connection) throw new Error('A grown-up must sign in on this device to choose apps.')
  const c = connection, identity = await me(c)
  if (identity.scope !== 'admin') throw new Error('A grown-up must sign in on this device to choose apps.')
  // Also validates that the selected member exists and is a child.
  const policy = await api<RoutineDecision>(c.baseURL, c.key, 'GET', `api/routine-mode/${encodeURIComponent(memberId)}`)
  if (connection !== c) throw new Error('Sign-in changed. Try again.')
  return KinwallNative.routineSetup(memberId, policy.appMode ?? 'selected', policy.allowedWebsitesOnly ?? false)
}
