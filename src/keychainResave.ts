// No native imports, so test/keychainResave.test.ts can run it.

type Store = {
  get(): Promise<string | null>
  remove(): Promise<void>
  /** With the new accessibility. */
  save(value: string): Promise<void>
  /** As it was before, if the new save fails. */
  restore(value: string): Promise<void>
}

/** Gives a saved Keychain item a new accessibility. iOS keeps an existing item's accessibility when
 * only its value is updated (expo-secure-store updates in place), so it's deleted and saved again.
 * A failed save puts the value back the old way; a failed read changes nothing. True once done. */
export async function resave(s: Store): Promise<boolean> {
  const value = await s.get()
  if (value === null) return true
  await s.remove()
  try { await s.save(value) } catch (e) { await s.restore(value); throw e }
  return true
}
