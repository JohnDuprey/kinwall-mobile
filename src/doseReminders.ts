// Identifier-only, in-memory invalidation: a concurrent refresh must not requeue a dose whose
// save just succeeded. Nothing medical is logged or persisted here.
export type DoseChange = { medicationId: string; date: string; time: string; action: 'taken' | 'skipped' | 'snooze' | 'unmark' }
type Reminder = { identifier?: string; content: { data?: Record<string, unknown> | null } }
const key = (dose: { medicationId: unknown; date: unknown; time: unknown }) => JSON.stringify([dose.medicationId, dose.date, dose.time])
export function parseDoseChange(value: unknown): DoseChange | null {
  if (!value || typeof value !== 'object') return null
  const d = value as Record<string, unknown>
  if (!['taken', 'skipped', 'snooze', 'unmark'].includes(String(d.action))) return null
  if (![d.medicationId, d.date, d.time].every(v => typeof v === 'string' && v.length > 0 && v.length <= 128)) return null
  return { medicationId: d.medicationId as string, date: d.date as string, time: d.time as string, action: d.action as DoseChange['action'] }
}
export class DoseReminderState {
  revision = 0
  private settled = new Set<string>()
  change(dose: DoseChange) {
    this.revision++
    if (dose.action === 'unmark' || dose.action === 'snooze') this.settled.delete(key(dose))
    else this.settled.add(key(dose))
  }
  blocks(reminder: Reminder) {
    if (!reminder.identifier?.startsWith('rem:med:') && !reminder.identifier?.startsWith('snz:rem:med:')) return false
    const data = reminder.content.data
    return !!data && this.settled.has(key({ medicationId: data.medicationId, date: data.date, time: data.time }))
  }
  stale<T extends Reminder>(reminders: T[]) { return reminders.filter(r => this.blocks(r)) }
  /** A fresh server read can undo a local mark changed on another device. An older read cannot. */
  reconcile(revision: number, reminders: Reminder[]) {
    if (revision !== this.revision) return
    for (const r of this.stale(reminders)) {
      const data = r.content.data!
      this.settled.delete(key({ medicationId: data.medicationId, date: data.date, time: data.time }))
    }
  }
  clear() { this.revision++; this.settled.clear() }
}
