import { routineDecision } from './routineMode.ts'

type Connection = { baseURL: string; key: string }
type Identity = { scope: string; owner: string | null }
export type RoutineStatus = { simulator: boolean; authorized: boolean; selected: number; locked: boolean; memberId: string; server?: string; appliedRevision?: number; hasAppChoices?: boolean; appMode?: 'selected' | 'all'; allowedWebsitesOnly?: boolean; allowedApps?: number; awaitingSelection?: boolean; remoteSelection?: boolean; role?: 'parent' | 'child'; enrolled?: boolean }
type Choices = { data: string; selectedApps: number; selectedCategories: number; allowedApps: number }
type SavedChoices = Omit<Choices, 'data'> & { revision: number; data: string | null }
export type RoutineNative = {
  status(): Promise<RoutineStatus>
  unenroll?(memberId: string, server: string): Promise<RoutineStatus>
  authorize?(memberId: string, server: string): Promise<RoutineStatus>
  choose?(memberId: string, appMode: 'selected' | 'all', websiteList: boolean, data: string | null): Promise<Choices | { cancelled: true }>
  importSelection?(memberId: string, server: string, data: string, revision: number): Promise<RoutineStatus>
  apply?(json: string): Promise<RoutineStatus>
}
type Dependencies = { native: RoutineNative; identity(c: Connection): Promise<Identity>; request(c: Connection, method: string, path: string, body?: unknown): Promise<unknown>; now?: () => number }
const pathFor = (id: string) => `api/routine-mode/${encodeURIComponent(id)}`
const validMember = (id: string) => /^[a-zA-Z0-9_-]{1,100}$/.test(id)
function savedChoices(value: unknown): SavedChoices {
  const v = value as Partial<SavedChoices> | null
  if (!v || !Number.isSafeInteger(v.revision) || v.revision! < 0 || (v.data !== null && (typeof v.data !== 'string' || v.data.length > 174764))) throw new Error('The saved app choices could not be read. Choose apps again.')
  return { revision: v.revision!, data: v.data!, selectedApps: v.selectedApps ?? 0, selectedCategories: v.selectedCategories ?? 0, allowedApps: v.allowedApps ?? 0 }
}

/** Parent pickers never authorize or restrict this phone. Only an authenticated child's own
 * device receives selections and applies the server's chore decision. No tokens go to WebView. */
export class RoutineFlow {
  private connection: Connection | null = null
  private preview = false
  private generation = 0
  private pending: Promise<RoutineStatus> | null = null
  private pendingMember: string | undefined
  private reports = new Map<string, { value: string; at: number }>()
  private samples = new Map<string, SavedChoices>()
  private readonly deps: Dependencies
  constructor(deps: Dependencies) { this.deps = deps }
  setConnection(c: Connection | null, preview = false) {
    if (c && this.connection?.baseURL === c.baseURL && this.connection?.key === c.key && this.preview === preview) return
    this.connection = c; this.preview = preview; this.generation++; this.pending = null
  }
  private current(c: Connection, generation: number) {
    if (this.connection !== c || this.generation !== generation) throw new Error('Sign-in changed. Try again.')
  }
  /** A wake-up is only a hint. Recover the existing paired sign-in on cold launch, then
   * use the same serialized, authenticated flow as the foreground. Never open a picker. */
  async backgroundRefresh(loadPaired: () => Promise<Connection | null>, sourceOrigin?: string): Promise<RoutineStatus | null> {
    if (this.preview) return null
    const generation = this.generation
    const c = this.connection ?? await loadPaired()
    if (generation !== this.generation || !c) return null
    const server = new URL(c.baseURL).origin
    if (sourceOrigin !== undefined && sourceOrigin !== server) return null
    if (!this.connection) this.setConnection(c)
    return this.sync()
  }
  private async report(c: Connection, id: string, status: RoutineStatus, enrollmentRevision?: number) {
    const body = { authorized: status.authorized, appliedRevision: status.appliedRevision ?? 0, locked: status.locked, ...(enrollmentRevision === undefined ? {} : { enrollmentRevision }) }
    const value = JSON.stringify(body), key = `${c.baseURL}:${id}:${c.key}`, now = this.deps.now?.() ?? Date.now(), previous = this.reports.get(key)
    if (previous?.value === value && now - previous.at < 60000) return
    await this.deps.request(c, 'PUT', `${pathFor(id)}/device`, body)
    this.reports.set(key, { value, at: now })
  }
  sync(memberId?: string, sample?: unknown): Promise<RoutineStatus> {
    if (this.pending) return memberId === this.pendingMember ? this.pending : this.pending.catch(() => null).then(() => this.sync(memberId, sample))
    const pending = this.synchronize(memberId, sample).finally(() => { if (this.pending === pending) this.pending = null })
    this.pending = pending
    this.pendingMember = memberId
    return pending
  }
  private async synchronize(memberId?: string, sample?: unknown): Promise<RoutineStatus> {
    const native = this.deps.native
    let status = await native.status()
    const c = this.connection, generation = this.generation
    if (status.simulator && this.preview) {
      const decision = routineDecision(sample)
      if (decision && native.apply) status = await native.apply(JSON.stringify(decision))
      return { ...status, remoteSelection: !!native.choose, role: 'parent' }
    }
    if (!c) return status
    const identity = await this.deps.identity(c); this.current(c, generation)
    if (identity.scope !== 'display' || !identity.owner || identity.owner === 'shared') return { ...status, role: 'parent', remoteSelection: !!native.choose }
    const id = identity.owner
    if (memberId && memberId !== id) throw new Error('This device can only check its own routine.')
    if (status.memberId && status.memberId !== id) throw new Error('This device was set up for a different child. A grown-up must set it up again.')
    if (status.server && status.server !== new URL(c.baseURL).origin) throw new Error('This device was set up for a different family. A grown-up must set it up again.')
    const policy = await this.deps.request(c, 'GET', pathFor(id))
    this.current(c, generation)
    const revision = (policy as { enrollmentRevision?: unknown } | null)?.enrollmentRevision
    if (revision !== undefined && (!Number.isSafeInteger(revision) || (revision as number) < 0)) throw new Error('The device enrollment could not be read. Try again.')
    const enrollmentRevision = revision as number | undefined
    if ((policy as { enrolled?: boolean } | null)?.enrolled === false) {
      if (!native.unenroll) throw new Error('Update Kinwall to finish removing Screen Time management.')
      status = await native.unenroll(id, new URL(c.baseURL).origin)
      this.current(c, generation)
      await this.report(c, id, status, enrollmentRevision)
      return { ...status, role: 'child', enrolled: false, awaitingSelection: false }
    }
    if (!status.authorized) {
      await this.report(c, id, status, enrollmentRevision)
      return { ...status, role: 'child', enrolled: true, remoteSelection: !!native.choose }
    }
    const rawChoices = await this.deps.request(c, 'GET', `${pathFor(id)}/apps`)
    this.current(c, generation)
    const choices = savedChoices(rawChoices), decision = routineDecision(policy)
    if (!decision) throw new Error('The routine decision is out of date. Try again.')
    const afterRevision = (policy as { appChoicesAfterRevision?: unknown }).appChoicesAfterRevision ?? 0
    if (!Number.isSafeInteger(afterRevision) || (afterRevision as number) < 0) throw new Error('The saved app choices could not be read. Choose apps again.')
    const needsNewChoices = (afterRevision as number) > 0 && choices.revision <= (afterRevision as number)
    if (!needsNewChoices && choices.data && choices.revision !== (status.appliedRevision ?? 0)) {
      if (!native.importSelection) throw new Error('Update Kinwall to receive the app choices from your grown-up.')
      status = await native.importSelection(id, new URL(c.baseURL).origin, choices.data, choices.revision)
      this.current(c, generation)
    }
    if (decision.enabled && decision.appMode === 'selected' && (needsNewChoices || (!choices.data && !status.hasAppChoices && !status.selected))) {
      await this.report(c, id, status, enrollmentRevision)
      return { ...status, role: 'child', enrolled: true, awaitingSelection: true }
    }
    if (!native.apply) throw new Error('Update Kinwall to use routine mode.')
    this.current(c, generation)
    status = await native.apply(JSON.stringify({ ...decision, kinwallHost: new URL(c.baseURL).hostname }))
    this.current(c, generation)
    await this.report(c, id, status, enrollmentRevision)
    return { ...status, role: 'child', enrolled: true, awaitingSelection: needsNewChoices }
  }
  async authorize(memberId: string): Promise<RoutineStatus> {
    const c = this.connection, generation = this.generation, native = this.deps.native
    if (!c || !native.authorize) throw new Error('Update Kinwall and pair this device to the child before approving Screen Time.')
    const identity = await this.deps.identity(c); this.current(c, generation)
    if (identity.scope !== 'display' || identity.owner !== memberId) throw new Error('This device can only approve its own child’s Screen Time access.')
    const policy = await this.deps.request(c, 'GET', pathFor(memberId))
    this.current(c, generation)
    if ((policy as { enrolled?: boolean } | null)?.enrolled === false) throw new Error('A grown-up must enroll this device again before approving Screen Time.')
    await native.authorize(memberId, new URL(c.baseURL).origin)
    this.current(c, generation)
    this.pending = null
    return this.sync(memberId)
  }
  async choose(memberId: string, sample?: unknown): Promise<Record<string, unknown>> {
    if (!validMember(memberId)) throw new Error('Choose a child in your family.')
    const native = this.deps.native, c = this.connection, generation = this.generation
    if (!native.choose) throw new Error('Update Kinwall to choose apps from your phone.')
    const status = await native.status()
    if (status.simulator && this.preview) {
      const decision = routineDecision(sample), previous = this.samples.get(memberId)
      const choice = await native.choose(memberId, decision?.appMode ?? 'selected', decision?.allowedWebsitesOnly ?? false, previous?.data ?? null)
      if ('cancelled' in choice) return { cancelled: true, memberId, role: 'parent' }
      const saved = { ...choice, revision: (previous?.revision ?? 0) + 1 }; this.samples.set(memberId, saved)
      return { memberId, role: 'parent', selectionSaved: true, revision: saved.revision, selectedApps: choice.selectedApps, selectedCategories: choice.selectedCategories, allowedApps: choice.allowedApps, simulator: true }
    }
    if (status.simulator) throw new Error('Simulator app choices are a preview. Choose apps on your phone for a real child device.')
    if (!c) throw new Error('A grown-up must sign in to choose apps.')
    const identity = await this.deps.identity(c); this.current(c, generation)
    if (identity.scope !== 'admin') throw new Error('A grown-up must choose apps.')
    const [policy, rawChoices] = await Promise.all([this.deps.request(c, 'GET', pathFor(memberId)), this.deps.request(c, 'GET', `${pathFor(memberId)}/apps`)])
    this.current(c, generation)
    const choices = savedChoices(rawChoices), p = policy as { appMode?: 'selected' | 'all'; allowedWebsitesOnly?: boolean }
    const choice = await native.choose(memberId, p.appMode ?? 'selected', p.allowedWebsitesOnly ?? false, choices.data)
    this.current(c, generation)
    if ('cancelled' in choice) return { memberId, role: 'parent', cancelled: true }
    const result = await this.deps.request(c, 'PUT', `${pathFor(memberId)}/apps`, { ...choice, expectedRevision: choices.revision }) as { revision: number }
    this.current(c, generation)
    return { memberId, role: 'parent', remoteSelection: true, selectionSaved: true, revision: result.revision, selectedApps: choice.selectedApps, selectedCategories: choice.selectedCategories, allowedApps: choice.allowedApps }
  }
}
