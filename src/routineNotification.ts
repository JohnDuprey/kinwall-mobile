/** Apple UIBackgroundFetchResult values expected by Expo's iOS notification task consumer. */
export async function runRoutineNotification(payload: unknown, refresh: (origin: string) => Promise<unknown>): Promise<0 | 1 | 2> {
  if (!payload || typeof payload !== 'object' || 'actionIdentifier' in payload) return 1
  const raw = payload as { notification?: unknown; aps?: Record<string, unknown> }
  if (raw.notification !== null || !raw.aps || raw.aps['content-available'] !== 1) return 1
  const data = (payload as { data?: unknown }).data
  if (!data || typeof data !== 'object') return 1
  const hint = (data as { kinwall?: unknown }).kinwall
  if (!hint || typeof hint !== 'object') return 1
  const { type, server } = hint as { type?: unknown; server?: unknown }
  if (type !== 'routine-sync' || typeof server !== 'string' || server.length > 2000) return 1
  let url: URL
  try { url = new URL(server) } catch { return 1 }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.origin !== server) return 1
  try { return await refresh(server) ? 0 : 1 } catch { return 2 }
}
