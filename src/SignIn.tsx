import { useState } from 'react'
import { ActivityIndicator, Image, Pressable, ScrollView, Text, View } from 'react-native'
import { signIn } from './oauth'
import { signInProblem } from './signInProblem'
import { logo, useUi } from './theme'
import { type Session, choosePairing, signedIn } from './session'

/** Sign in with Kinwall's OAuth in the system's auth sheet (passkeys work there on any domain), or
 * pair with a code a grown-up approves (kids' phones, wall tablets). */
export function SignIn({ server, onSession, onChangeServer }: { server: string; onSession: (s: Session) => void; onChangeServer: () => void }) {
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const ui = useUi()

  const start = async () => {
    setBusy(true); setProblem(null)
    try {
      const tokens = await signIn(server)
      if (tokens) onSession(await signedIn(tokens)) // null: closed the sheet, stay here quietly
    } catch (e) {
      setProblem(signInProblem(e, new URL(server).host))
    } finally { setBusy(false) }
  }

  const pair = async () => {
    setProblem(null)
    try { onSession(await choosePairing()) } catch { setProblem("Couldn't set up pairing on this device. Try again.") }
  }

  return (
    <ScrollView contentContainerStyle={ui.scroll}><View style={ui.screen}>
      <Image source={logo(ui.dark)} style={ui.logo} accessibilityIgnoresInvertColors accessible={false} />
      <Text style={ui.title} accessibilityRole="header">Sign in to Kinwall</Text>
      <Text style={ui.muted}>{new URL(server).host}</Text>
      <Pressable style={ui.button} onPress={start} accessibilityRole="button" disabled={busy}>
        {busy ? <ActivityIndicator color={ui.c.ink} /> : <Text style={ui.buttonText}>Sign in</Text>}
      </Pressable>
      <Text style={[ui.muted, ui.footnote]}>Opens your Kinwall in a secure sheet. Sign in with your passkey and approve this app.</Text>
      {problem && <Text style={ui.problem}>{problem}</Text>}
      <Pressable style={[ui.button, ui.secondary]} accessibilityRole="button" onPress={pair} disabled={busy}>
        <Text style={[ui.buttonText, ui.secondaryText]}>Pair with a code instead</Text>
      </Pressable>
      <Text style={[ui.muted, ui.footnote]}>For a child's phone or a wall tablet: this device shows a code, and a grown-up approves it in Kinwall under Settings → Access.</Text>
      <Pressable onPress={onChangeServer} accessibilityRole="button"><Text style={ui.link}>Use a different server</Text></Pressable>
    </View></ScrollView>
  )
}
