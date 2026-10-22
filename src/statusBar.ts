import type { Appearance } from './appearance.ts'

// A device-wide preference, independent of the server, account and web view's storage.
const SAVED = 'statusBarHidden'
type Reader = { getItem: (key: string) => string | null }
type Writer = { setItem: (key: string, value: string) => void }

export function readStatusBarHidden(storage: Reader): boolean {
  try {
    const saved = storage.getItem(SAVED)
    if (saved === 'true' || saved === 'false') return saved === 'true'
  } catch { /* show the status bar when storage is unavailable */ }
  return false
}

/** Save before acknowledging: the switch should reflect a choice that survives a relaunch. */
export function saveStatusBarHidden(storage: Writer, hidden: boolean): boolean {
  try { storage.setItem(SAVED, String(hidden)); return true } catch { return false }
}

export function statusBarMessage(message: unknown): boolean | null {
  if (!message || typeof message !== 'object') return null
  const m = message as { type?: unknown; hidden?: unknown }
  return m.type === 'statusBar' && typeof m.hidden === 'boolean' ? m.hidden : null
}

/** Acknowledge changes through the same event used for other native capabilities. */
export const statusBarScript = (hidden: boolean) => `if (window.kinwallNative) { window.kinwallNative.statusBarHidden = ${JSON.stringify(hidden)}; window.dispatchEvent(new Event('kinwallnative')); } true;`

/** Paint the page's accent, with whichever of white/black has higher WCAG contrast. Older pages
 * supply no accent surface, so retain their frame color. Auto follows the system at launch. */
export function statusBarSurface(look: Appearance | null, systemDark: boolean, fallback: string): { color: string; style: 'light' | 'dark' } {
  const dark = look?.mode === 'auto' ? systemDark : look?.dark
  const color = look?.statusBarColors?.[dark ? 'dark' : 'light'] ?? fallback
  const rgb = /^#([0-9a-f]{6})$/i.exec(color)?.[1] ?? '000000'
  const channels = [0, 2, 4].map(i => {
    const c = parseInt(rgb.slice(i, i + 2), 16) / 255
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
  })
  const luminance = 0.2126 * channels[0]! + 0.7152 * channels[1]! + 0.0722 * channels[2]!
  return { color, style: (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) ? 'dark' : 'light' }
}
