/** APNs uses App Attest enrollment; raw FCM tokens need their own server transport. */
export type NativePushTransport = 'apns' | 'fcm'
export function nativePushTransport(platform: string, firebaseConfigured: boolean, appleEnabled: boolean): NativePushTransport | null {
  return platform === 'ios' ? appleEnabled ? 'apns' : null : platform === 'android' && firebaseConfigured ? 'fcm' : null
}
export function acceptsNativeToken(transport: NativePushTransport | null, token: { type: string; data: unknown }): token is { type: string; data: string } {
  return transport !== null && token.type === (transport === 'apns' ? 'ios' : 'android') && typeof token.data === 'string' && token.data.length > 0
}
export function registerNativeToken<T>(transport: NativePushTransport, token: string, ipad: boolean, deps: {
  apple(body: { token: string; deviceName: string }): Promise<T>
  android(body: { token: string; deviceName: string }): Promise<T>
}): Promise<T> {
  // No prefs/memberIds here: renewal must preserve this device's choices (newChores defaults off).
  return transport === 'fcm' ? deps.android({ token, deviceName: 'Kinwall Android' })
    : deps.apple({ token, deviceName: ipad ? 'Kinwall iPad' : 'Kinwall iPhone' })
}
