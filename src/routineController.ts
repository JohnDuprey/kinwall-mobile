import KinwallNative from '../modules/kinwall-native'
import { Platform } from 'react-native'
import { api, type Connection } from './api'
import { pairedConnection } from './sharedKey'
import { RoutineFlow, type RoutineNative } from './routineFlow'

const native: RoutineNative = {
  status: async () => {
    if (!KinwallNative?.routineStatus) throw new Error('Update Kinwall to use routine mode.')
    return KinwallNative.routineStatus()
  },
  ...(KinwallNative?.routineApply ? { apply: (json: string) => KinwallNative!.routineApply!(json) } : {}),
  ...(KinwallNative?.routineAuthorize ? { authorize: (id: string, server: string) => KinwallNative!.routineAuthorize!(id, server) } : {}),
  ...(KinwallNative?.routineChoose ? { choose: (id: string, mode: 'selected' | 'all', websites: boolean, data: string | null) => KinwallNative!.routineChoose!(id, mode, websites, data) } : {}),
  ...(KinwallNative?.routineImportSelection ? { importSelection: (id: string, server: string, data: string, revision: number) => KinwallNative!.routineImportSelection!(id, server, data, revision) } : {}),
}
async function request<T>(c: Connection, method: string, path: string, body?: unknown): Promise<T> {
  const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 8000)
  try { return await api<T>(c.baseURL, c.key, method, path, body, controller.signal) }
  finally { clearTimeout(timer) }
}
const flow = new RoutineFlow({ native,
  identity: c => request<{ scope: string; owner: string | null }>(c, 'GET', 'api/me'),
  request,
})
export const setRoutineConnection = (c: Connection | null, preview = false) => flow.setConnection(c, preview)
export const syncRoutine = (memberId?: string, sample?: unknown) => flow.sync(memberId, sample)
export const setupRoutine = (memberId: string, sample?: unknown) => flow.choose(memberId, sample)
export const authorizeRoutine = (memberId: string) => flow.authorize(memberId)
export const refreshRoutine = () => flow.sync().catch(() => null)
export const refreshBackgroundRoutine = (sourceOrigin?: string) => Platform.OS === 'ios' && KinwallNative?.routineStatus
  ? flow.backgroundRefresh(pairedConnection, sourceOrigin) : Promise.resolve(null)
