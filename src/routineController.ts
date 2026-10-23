import KinwallNative from '../modules/kinwall-native'
import { api, me, type Connection } from './api'
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
const flow = new RoutineFlow({ native, identity: me,
  request: async (c: Connection, method, path, body) => {
    const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 10000)
    try { return await api(c.baseURL, c.key, method, path, body, controller.signal) }
    finally { clearTimeout(timer) }
  },
})
export const setRoutineConnection = (c: Connection | null, preview = false) => flow.setConnection(c, preview)
export const syncRoutine = (memberId?: string, sample?: unknown) => flow.sync(memberId, sample)
export const setupRoutine = (memberId: string, sample?: unknown) => flow.choose(memberId, sample)
export const authorizeRoutine = (memberId: string) => flow.authorize(memberId)
export const refreshRoutine = () => flow.sync().catch(() => null)
