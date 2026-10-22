type LoadError = { code: number; domain?: string; description: string }
type Options<T> = {
  platform: string
  active: () => boolean
  restart: () => void
  fail: (message: string) => void
  schedule: (run: () => void, delay: number) => T
  cancel: (timer: T) => void
}

/** A waking phone may briefly have no network. Retry connection failures twice;
 * certificate and other errors still need the user's attention. */
export function createLoadRecovery<T>(options: Options<T>) {
  let attempts = 0
  let pending = false
  let timer: T | undefined
  const clear = () => {
    if (timer !== undefined) options.cancel(timer)
    timer = undefined
    pending = false
  }
  const resume = () => {
    if (!pending || !options.active()) return
    clear()
    options.restart()
  }
  const reset = () => { clear(); attempts = 0 }
  return {
    failed(error: LoadError) {
      clear()
      const transient = options.platform === 'ios'
        ? error.domain === 'NSURLErrorDomain' && [-1001, -1003, -1004, -1005, -1006, -1009].includes(error.code)
        : options.platform === 'android' && [-2, -6, -7, -8].includes(error.code)
      if (!transient || attempts >= 2) { options.fail(error.description); return }
      pending = true
      timer = options.schedule(() => { timer = undefined; resume() }, ++attempts === 1 ? 1000 : 3000)
    },
    cancel: clear,
    loaded: reset,
    retry() { reset(); options.restart() },
    resume,
    dispose: clear,
  }
}

/** Each check belongs to one page and one foreground visit. A delayed answer or
 * timeout from an older check must never restart its replacement. */
export function createPageProbe<T>(options: Omit<Options<T>, 'platform' | 'fail'> & { send: (id: number) => void }) {
  let generation = 0
  let waiting: number | null = null
  let timer: T | undefined
  const cancel = () => {
    if (timer !== undefined) options.cancel(timer)
    timer = undefined
    waiting = null
  }
  return {
    cancel,
    start() {
      if (!options.active()) return
      cancel()
      const id = ++generation
      waiting = id
      timer = options.schedule(() => {
        if (waiting !== id) return
        cancel()
        if (options.active()) options.restart()
      }, 8000)
      options.send(id)
    },
    answer(id: unknown) {
      if (waiting === null || id !== waiting) return false
      cancel()
      return true
    },
  }
}
