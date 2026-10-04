import * as SecureStore from 'expo-secure-store'
import * as SplashScreen from 'expo-splash-screen'
import { useMemo } from 'react'
import { StyleSheet, useColorScheme } from 'react-native'
import { type Appearance, parseAppearance } from './appearance'

// The native screens (address, sign-in, can't reach) in Kinwall's own colors, light and dark, the
// same tokens the web app's default scheme uses, so the frame matches what loads inside it.
// Peacock (web/src/skins.ts); buttons carry white text on the fill: the light accent (12.2:1), and in
// dark the web app's deepened fill (accentFill, 4.6:1), with the sky-blue accent kept for the cursor.
const LIGHT = { bg: '#EEF3F8', field: '#FAFCFE', text: '#102A43', dim: '#4A6078', border: '#B8CBDD', accent: '#123857', fill: '#123857', ink: '#FFFFFF', problem: '#B3261E' }
const DARK = { bg: '#0B1622', field: '#16273A', text: '#E4ECF5', dim: '#9DB2C8', border: '#395677', accent: '#6CB4EE', fill: '#497AA2', ink: '#FFFFFF', problem: '#FF8A80' }
export type Palette = typeof LIGHT

const make = (c: Palette) => StyleSheet.create({
  root: { flex: 1, backgroundColor: c.bg },
  // The native screens scroll when they don't fit (landscape, keyboard up), centered when they do.
  scroll: { flexGrow: 1, justifyContent: 'center' },
  screen: { flexGrow: 1, justifyContent: 'center', padding: 24, gap: 16, maxWidth: 520, width: '100%', alignSelf: 'center' },
  // Wide and short (a tablet in landscape): the logo and welcome on the left, the form on the right.
  wide: { flexDirection: 'row', alignItems: 'center', maxWidth: 960, gap: 48 },
  column: { flex: 1, gap: 16 },
  screenPart: { gap: 16 },
  logo: { width: 120, height: 71, alignSelf: 'center' },
  title: { fontSize: 32, fontWeight: '700', textAlign: 'center', color: c.text },
  muted: { color: c.dim, textAlign: 'center', fontSize: 16, lineHeight: 22 },
  footnote: { fontSize: 14, lineHeight: 20 },
  input: { padding: 14, borderRadius: 14, backgroundColor: c.field, borderWidth: 1.5, borderColor: c.border, color: c.text, fontSize: 17 },
  button: { backgroundColor: c.fill, padding: 14, borderRadius: 12, alignItems: 'center', minHeight: 50, justifyContent: 'center' },
  buttonText: { color: c.ink, fontSize: 17, fontWeight: '600' },
  // Disabled keeps readable text: the field's color with a border, not a faded accent.
  disabled: { backgroundColor: c.field, borderWidth: 1.5, borderColor: c.border },
  disabledText: { color: c.dim },
  secondary: { backgroundColor: c.field, borderWidth: 1.5, borderColor: c.border },
  secondaryText: { color: c.text },
  problem: { color: c.problem, fontSize: 15, textAlign: 'center' },
  // 12 + 20 + 12: a 44pt touch target (Use a different server, Change server, Cancel).
  link: { color: c.text, fontSize: 15, lineHeight: 20, textAlign: 'center', paddingVertical: 12, paddingHorizontal: 8, textDecorationLine: 'underline' },
})

/** The Kinwall mark, as on the launch screen and the web app's sign-in. */
export const logo = (dark: boolean) => dark ? require('../assets/splash-icon-dark.png') : require('../assets/splash-icon.png')

const STYLES = { light: make(LIGHT), dark: make(DARK) }

export function useUi() {
  const dark = useColorScheme() === 'dark'
  return useMemo(() => ({ ...(dark ? STYLES.dark : STYLES.light), c: dark ? DARK : LIGHT, dark }), [dark])
}

// The page's last look (src/appearance.ts), read synchronously so the first frame already has it.
// Kept beside the server address; cleared on sign-out, never saved from the demo.
const SAVED = 'appearance'
export function savedAppearance(): Appearance | null {
  try { return parseAppearance(SecureStore.getItem(SAVED)) } catch { return null }
}
export const saveAppearance = (a: Appearance) => SecureStore.setItemAsync(SAVED, JSON.stringify(a)).catch(() => {})
export const clearAppearance = () => SecureStore.deleteItemAsync(SAVED).catch(() => {})

/** The launch screen stays up (App.tsx) until what's under it is painted: a native screen, or the
 * page's first frame. Safe to call more than once. */
export const hideSplash = () => { SplashScreen.hideAsync().catch(() => {}) }
