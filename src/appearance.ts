// The page's look, as the web app reports it (web/src/native.ts tellAppAppearance in the kinwall
// repo): saved so the next launch paints the frame, the splash's hand-off and the page's first
// frame in the family's colors instead of flashing the app's own. No React Native imports here, so
// test/appearance.test.ts runs it under plain node.

export type Surface = { bg: string; card: string }
export type Appearance = { mode: 'light' | 'dark' | 'auto' | 'scheduled'; dark: boolean; colors: { light: Surface; dark: Surface }; statusBarColors?: { light: string; dark: string } }

const HEX = /^#[0-9a-f]{6}$/i
const MODES = ['light', 'dark', 'auto', 'scheduled']
const surface = (v: unknown): Surface | null => {
  const s = v as Partial<Surface> | null
  return s && typeof s.bg === 'string' && HEX.test(s.bg) && typeof s.card === 'string' && HEX.test(s.card) ? { bg: s.bg, card: s.card } : null
}

/** The page's message or the saved JSON; null for anything else (it comes from a web page and
 * ends up in injected script, so only plain hex colors pass). */
export function parseAppearance(v: unknown): Appearance | null {
  let a: Partial<Appearance> | null
  try { a = typeof v === 'string' ? JSON.parse(v) : v } catch { return null }
  if (!a || typeof a !== 'object' || !MODES.includes(a.mode as string) || typeof a.dark !== 'boolean') return null
  const light = surface(a.colors?.light), dark = surface(a.colors?.dark)
  const bars = a.statusBarColors
  if (bars !== undefined && (!bars || typeof bars.light !== 'string' || !HEX.test(bars.light) || typeof bars.dark !== 'string' || !HEX.test(bars.dark))) return null
  return light && dark ? { mode: a.mode!, dark: a.dark, colors: { light, dark }, ...(bars ? { statusBarColors: { light: bars.light, dark: bars.dark } } : {}) } : null
}

/** The frame's colors now: 'auto' follows the system's current appearance; the other modes use
 * whatever the page last showed ('scheduled' included: its hours are the page's to work out). */
export function frameColors(a: Appearance | null, systemDark: boolean): (Surface & { dark: boolean }) | null {
  if (!a) return null
  const dark = a.mode === 'auto' ? systemDark : a.dark
  return { dark, ...(dark ? a.colors.dark : a.colors.light) }
}

/** The colors sent with a Live Activity: the frame's background with Kinwall's text and accent for
 * light or dark; null for Kinwall's own. Only the accent is used now (the cooking alarm's tint on
 * iOS, Android's countdown notification color): the activity itself draws on the system's
 * background with Kinwall's blue as an accent (targets/widgets/LiveActivities.swift). */
export function activityColors(frame: (Surface & { dark: boolean }) | null): { bg: string; fg: string; accent: string } | null {
  if (!frame) return null
  return frame.dark ? { bg: frame.bg, fg: '#E4ECF5', accent: '#6CB4EE' } : { bg: frame.bg, fg: '#102A43', accent: '#123857' }
}

/** The Android widgets' colors (src/widgets.tsx): the family's surfaces with Kinwall's text and
 * accent, light or dark as the frame would be; Kinwall's own (src/theme.ts) before the page has
 * sent any. `systemDark`: the representation Android asks for (its dark theme on or off). */
type Hex = `#${string}`
export type WidgetPalette = { bg: Hex; card: Hex; fg: Hex; dim: Hex; accent: Hex }
const LIGHT: WidgetPalette = { bg: '#EEF3F8', card: '#FAFCFE', fg: '#102A43', dim: '#4A6078', accent: '#123857' }
const DARK: WidgetPalette = { bg: '#0B1622', card: '#16273A', fg: '#E4ECF5', dim: '#9DB2C8', accent: '#6CB4EE' }
export function widgetPalette(a: Appearance | null, systemDark: boolean): WidgetPalette {
  const f = frameColors(a, systemDark)
  const base = (f ? f.dark : systemDark) ? DARK : LIGHT
  return f ? { ...base, bg: f.bg as Hex, card: f.card as Hex } : base // parseAppearance only passes #rrggbb
}
