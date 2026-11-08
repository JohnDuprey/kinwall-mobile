/** `run` at once, then ignored until `ms` have passed: for work iOS may trigger every few seconds
 * (the app flipping between active and inactive). */
export function atMostEvery(ms: number, run: () => void, now: () => number = Date.now): () => void {
  let last = -Infinity
  return () => {
    const t = now()
    if (t - last < ms) return
    last = t
    run()
  }
}
