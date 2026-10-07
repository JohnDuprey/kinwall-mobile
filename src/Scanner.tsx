import { CameraView, useCameraPermissions } from 'expo-camera'
import { createAudioPlayer, setAudioModeAsync, type AudioPlayer } from 'expo-audio'
import * as Haptics from 'expo-haptics'
import * as SecureStore from 'expo-secure-store'
import { useEffect, useRef, useState } from 'react'
import { Linking, Modal, Pressable, StyleSheet, Text, View } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import { cleanBarcode } from './barcode'
import { useUi } from './theme'

// The barcodes on books (ISBN) and groceries. iOS reports a UPC-A as an EAN-13 with a leading 0.
const TYPES = ['ean13', 'ean8', 'upc_a', 'upc_e'] as const

// The beep (assets/sounds/scan-beep.wav, made for Kinwall, soft): on unless turned off on the scanner,
// kept on this device. iOS "ambient": it mixes with music or an audiobook instead of pausing it, never
// pulls AirPods over from another device, and follows the silent switch. Set before every beep (speech
// for activities sets its own), and expo-audio lets the audio go again once it's played. One player
// for the app, so the beep isn't cut off when the scanner closes.
const BEEP_KEY = 'scanBeep'
let beepPlayer: AudioPlayer | null = null
function beep() {
  beepPlayer ??= createAudioPlayer(require('../assets/sounds/scan-beep.wav'))
  setAudioModeAsync({ playsInSilentMode: false, interruptionMode: 'mixWithOthers' }).catch(() => {})
    .then(() => beepPlayer?.seekTo(0)).then(() => beepPlayer?.play()).catch(() => {})
}

/** Full-screen barcode scanner (the page's Scan buttons: Add a book, and shopping lists; web/src/native.ts): the first barcode it
 * reads, or null when closed. Asks for the camera the first time it opens. */
export function Scanner({ facing: initialFacing, onDone }: { facing: 'front' | 'back'; onDone: (code: string | null) => void }) {
  const ui = useUi()
  const [permission, request] = useCameraPermissions()
  const done = useRef(false)
  const finish = (code: string | null) => { if (done.current) return; done.current = true; onDone(code) }
  const [facing, setFacing] = useState(initialFacing) // the page's pick (front on a wall tablet); Flip switches
  const [sound, setSound] = useState(() => { try { return SecureStore.getItem(BEEP_KEY) !== 'off' } catch { return true } })
  const toggleSound = () => { const on = !sound; setSound(on); SecureStore.setItemAsync(BEEP_KEY, on ? 'on' : 'off').catch(() => {}) }
  const scanned = (code: string) => {
    if (done.current) return
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {})
    if (sound) beep()
    finish(code)
  }

  useEffect(() => { if (permission && !permission.granted && permission.canAskAgain) request() }, [permission, request])

  return (
    <Modal animationType="slide" presentationStyle="fullScreen" onRequestClose={() => finish(null)}>
      {permission?.granted ? (
        <View style={styles.root}>
          <CameraView
            style={StyleSheet.absoluteFill}
            facing={facing}
            barcodeScannerSettings={{ barcodeTypes: [...TYPES] }}
            onBarcodeScanned={({ data }) => { const code = cleanBarcode(data); if (code) scanned(code) }}
          />
          <SafeAreaView style={styles.overlay}>
            <View style={styles.top}>
              <Text style={styles.hint} accessibilityRole="header">Point at the barcode</Text>
              <View style={styles.buttons}>
                <Pressable style={styles.sound} onPress={toggleSound} accessibilityRole="switch" accessibilityState={{ checked: sound }} accessibilityLabel="Beep when scanned">
                  <Text style={styles.soundText}>{sound ? '🔊 Beep' : '🔇 Beep off'}</Text>
                </Pressable>
                <Pressable style={styles.sound} onPress={() => setFacing((f) => (f === 'front' ? 'back' : 'front'))} accessibilityRole="button" accessibilityLabel={facing === 'front' ? 'Use the back camera' : 'Use the front camera'}>
                  <Text style={styles.soundText}>🔄 Flip</Text>
                </Pressable>
              </View>
            </View>
            <View style={styles.frame} accessible={false} />
            <Pressable style={styles.close} onPress={() => finish(null)} accessibilityRole="button">
              <Text style={styles.closeText}>Cancel</Text>
            </Pressable>
          </SafeAreaView>
        </View>
      ) : (
        <View style={ui.root}><View style={ui.screen}>
          <Text style={ui.title}>Scan a barcode</Text>
          <Text style={ui.muted}>
            {permission && !permission.canAskAgain
              ? 'Kinwall needs the camera to scan. Turn it on in Settings, then try again.'
              : 'Kinwall uses the camera to read barcodes on books and groceries.'}
          </Text>
          {permission && !permission.canAskAgain
            ? <Pressable style={ui.button} onPress={() => Linking.openSettings()}><Text style={ui.buttonText}>Open Settings</Text></Pressable>
            : <Pressable style={ui.button} onPress={() => request()}><Text style={ui.buttonText}>Allow camera</Text></Pressable>}
          <Pressable onPress={() => finish(null)}><Text style={ui.link}>Cancel</Text></Pressable>
        </View></View>
      )}
    </Modal>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#000' },
  overlay: { flex: 1, alignItems: 'center', justifyContent: 'space-between', padding: 24 },
  top: { alignItems: 'center', gap: 12, marginTop: 24 },
  buttons: { flexDirection: 'row', gap: 10 },
  hint: { color: '#fff', fontSize: 20, fontWeight: '700', textAlign: 'center', textShadowColor: '#000', textShadowRadius: 6 },
  sound: { backgroundColor: 'rgba(0,0,0,0.6)', borderWidth: 1.5, borderColor: '#fff', borderRadius: 22, minHeight: 44, paddingHorizontal: 16, alignItems: 'center', justifyContent: 'center' },
  soundText: { color: '#fff', fontSize: 15, fontWeight: '600' },
  frame: { width: '85%', maxWidth: 420, aspectRatio: 2, borderWidth: 3, borderColor: '#fff', borderRadius: 16 },
  close: { backgroundColor: 'rgba(0,0,0,0.6)', borderWidth: 1.5, borderColor: '#fff', borderRadius: 12, minHeight: 50, minWidth: 160, paddingHorizontal: 24, alignItems: 'center', justifyContent: 'center', marginBottom: 16 },
  closeText: { color: '#fff', fontSize: 17, fontWeight: '600' },
})
