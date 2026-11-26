type NativePrinter = {
  printSupported?(): boolean
  printCurrentPage?(viewTag: number, title: string): Promise<void>
}

/** Older native builds and hosts without a print service keep the page's Print button hidden. */
export function printAvailable(native: NativePrinter | null): boolean {
  return !!native?.printCurrentPage && native.printSupported?.() === true
}

/** Call only after bridgeMessage's origin/nonce check. The tag belongs to the mounted WebView's
 * non-collapsable wrapper, never the imperative WebView ref or an app-wide view search. */
export async function routePrint(message: Record<string, unknown> | null, viewTag: number | null, native: NativePrinter | null): Promise<boolean> {
  if (message?.type !== 'print' || viewTag === null || !printAvailable(native)) return false
  const title = typeof message.title === 'string' && message.title.trim() ? message.title : 'Kinwall recipe'
  await native!.printCurrentPage!(viewTag, title)
  return true
}
