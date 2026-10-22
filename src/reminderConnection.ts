import type { Connection } from './api'
import type { Tokens } from './oauth'

type Sources = {
  loadTokens(): Promise<Tokens | null>
  freshTokens(tokens: Tokens): Promise<Tokens | null>
  paired(): Promise<Connection | null>
  widgets(): Promise<Connection | null>
}

/** Personal reminders belong to the phone's sign-in. Parent widgets deliberately use a shared
 * identity, which has no person and therefore cannot supply personal medicine reminders. */
export async function reminderConnection(server: string | null, sources: Sources): Promise<Connection | null> {
  if (!server) return null
  const tokens = await sources.loadTokens()
  if (tokens?.baseURL === server) {
    const fresh = await sources.freshTokens(tokens)
    return fresh?.baseURL === server ? { baseURL: server, key: fresh.accessToken } : null
  }
  const paired = await sources.paired()
  if (paired?.baseURL === server) return paired
  const widgets = await sources.widgets()
  return widgets?.baseURL === server ? widgets : null
}
