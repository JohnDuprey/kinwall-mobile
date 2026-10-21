import type { Connection, createDeviceKey, revokeOwnKey, watchKeyFits } from './api'

type WatchApi = { createDeviceKey: typeof createDeviceKey; revokeOwnKey: typeof revokeOwnKey; watchKeyFits: typeof watchKeyFits }

/** Replace a legacy/shared Watch key using the phone's credential, not the widgets' key.
 * A superseded sign-in must never hand a newly created credential to the Watch. */
export async function personalWatchConnection(source: Connection, saved: Connection | null, isCurrent: () => boolean, { createDeviceKey, revokeOwnKey, watchKeyFits }: WatchApi): Promise<Connection | null> {
  if (saved && await watchKeyFits(saved, source)) return isCurrent() ? saved : null
  const minted = await createDeviceKey(source.baseURL, source.key, 'Apple Watch', 'watch').catch(() => null)
  if (!minted) return null
  const next = { baseURL: source.baseURL, key: minted.key }
  if (!isCurrent()) { await revokeOwnKey(next).catch(() => {}); return null }
  if (saved) await revokeOwnKey(saved).catch(() => {})
  if (!isCurrent()) { await revokeOwnKey(next).catch(() => {}); return null }
  return next
}
