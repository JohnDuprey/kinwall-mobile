// One device's local daily chore reminder preference, shared by foreground and background refresh.
const SAVED = 'choreNudgeAnyone'
type Reader = { getItem: (key: string) => string | null }
type Writer = { setItem: (key: string, value: string) => void }
export function readChoreNudgeAnyone(storage: Reader): boolean {
  try { return storage.getItem(SAVED) === 'true' } catch { return false }
}
export function saveChoreNudgeAnyone(storage: Writer, on: boolean): boolean {
  try { storage.setItem(SAVED, String(on)); return true } catch { return false }
}
export function choreNudgeAnyoneMessage(message: unknown): boolean | null {
  if (!message || typeof message !== 'object') return null
  const m = message as { type?: unknown; on?: unknown }
  return m.type === 'choreNudgeAnyone' && typeof m.on === 'boolean' ? m.on : null
}
export const choreNudgeAnyoneScript = (on: boolean) => `if (window.kinwallNative) { window.kinwallNative.choreNudgeAnyone = ${JSON.stringify(on)}; window.dispatchEvent(new Event('kinwallnative')); } true;`
