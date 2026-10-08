// iPhone: the medicine reminders and chore nudge the app schedules on the device (src/reminders.ts),
// since it can't receive the server's web push. Only on a person's own device, like the server's.
// No React Native imports, so test/reminderPlans.test.ts runs it under plain node.

/** GET /api/members/{id}/medications?days=1: today's doses (with their status) and the schedules. */
export type MedicationDay = {
  today: string
  medications: { id: string; times: (string | { wake: true; latest: string })[]; days: number[]; endDate: string | null; dosesLeft: number | null }[]
  days: { date: string; doses: { medicationId: string; time: string; dueAt: string; status: string }[] }[]
}
export type DoseReminder = { medicationId: string; date: string; time: string; at: number }

const addDays = (date: string, n: number) => new Date(Date.parse(`${date}T12:00:00Z`) + n * 86_400_000).toISOString().slice(0, 10)

/** Today's doses still to come (the server's own times), then tomorrow's from the schedules.
 * "When I start my day" doses are left out: they're due whenever the day starts, which the device
 * can't know ahead. */
export function doseReminders(h: MedicationDay, now: number): DoseReminder[] {
  const out: DoseReminder[] = []
  for (const day of h.days.filter((d) => d.date === h.today)) {
    for (const d of day.doses) {
      const at = Date.parse(d.dueAt)
      if (d.status === 'upcoming' && d.time !== 'wake' && at > now) out.push({ medicationId: d.medicationId, date: day.date, time: d.time, at })
    }
  }
  const tomorrow = addDays(h.today, 1)
  const weekday = new Date(`${tomorrow}T12:00:00Z`).getUTCDay()
  const [y, mo, dd] = tomorrow.split('-').map(Number) as [number, number, number]
  for (const m of h.medications) {
    if (!m.days.includes(weekday) || (m.endDate && tomorrow > m.endDate) || m.dosesLeft === 0) continue
    for (const t of m.times) {
      if (typeof t !== 'string') continue
      const [hh, mm] = t.split(':').map(Number) as [number, number]
      // ponytail: the device's timezone, not the household's (as for all-day events); differs only when the phone travels.
      out.push({ medicationId: m.id, date: tomorrow, time: t, at: new Date(y, mo - 1, dd, hh, mm).getTime() })
    }
  }
  return out
}

/** GET /api/chores/day. `pending`: ticked from the widgets' key and waiting for a parent's OK (not
 * `completed`, no points yet); missing from servers older than approvals. */
export type ChoreDay = { id: string; title: string; emoji?: string | null; memberId: string | null; completed: boolean; pending?: boolean; checklist?: { total: number; done: number } | null }
export type ChoreNudge = { title: string; body: string; choreId: string | null }

/** The server's chore nudge ("2 chores left today"), for the person's own chores that day. Done
 * only fits one chore, and not one with a checklist (it opens to finish that first). */
export function choreNudge(chores: ChoreDay[], person: string): ChoreNudge | null {
  const mine = chores.filter((c) => c.memberId === person && !c.completed && !c.pending) // waiting for an OK isn't left
  if (mine.length === 0) return null
  const one = mine.length === 1 && !(mine[0]!.checklist && mine[0]!.checklist.done < mine[0]!.checklist.total) ? mine[0]!.id : null
  return { title: `${mine.length} chore${mine.length === 1 ? '' : 's'} left today`, body: mine.slice(0, 3).map((c) => c.title).join(', '), choreId: one }
}

/** The Kinwall Focus filter's "Only my reminders" hides an event reminder tagged "others":
 * someone else's event. Family events (nobody tagged) and a shared device's are never hidden. */
export const focusTag = (memberIds: string[] | undefined, person: string | null) =>
  person && memberIds?.length && !memberIds.includes(person) ? 'others' : undefined

/** "07:30" on a local YYYY-MM-DD, as a time. */
export function localAt(date: string, hhmm: string): number {
  const [y, mo, d] = date.split('-').map(Number) as [number, number, number]
  const [h, m] = hhmm.split(':').map(Number) as [number, number]
  return new Date(y, mo - 1, d, h, m).getTime()
}
