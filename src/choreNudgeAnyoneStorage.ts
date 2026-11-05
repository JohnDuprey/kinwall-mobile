import * as SecureStore from 'expo-secure-store'
// Background reminder refresh runs while locked; keep this non-sensitive choice readable then.
export const choreNudgeAnyoneStorage = {
  getItem: (key: string) => SecureStore.getItem(key, { keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY }),
  setItem: (key: string, value: string) => SecureStore.setItem(key, value, { keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY }),
}
