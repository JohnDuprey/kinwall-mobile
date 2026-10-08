import * as SecureStore from 'expo-secure-store'
import { useEffect, useState } from 'react'
import { Pressable, ScrollView, Text } from 'react-native'
import { SafeAreaView } from 'react-native-safe-area-context'
import {
  FlexWidget, ListWidget, TextWidget, registerWidgetConfigurationScreen, registerWidgetTaskHandler,
  type WidgetConfigurationScreenProps, type WidgetRepresentation, type WidgetTaskHandlerProps,
} from 'react-native-android-widget'
import { type Board, type Connection, board, choresOn, completeChore, dueDoses, features, list, settings, lists, me, members, nowAndNext, setItemDone } from './api'
import { type WidgetPalette, widgetPalette } from './appearance'
import { savedAppearance, useUi } from './theme'
import { widgetConnection } from './sharedKey'
import { DEMO_CHORES, DEMO_GROCERIES, DEMO_PEOPLE, type ListDetail, choreRows, choreTap, isTicked, medicinesOn, pickGroceries, takeNowText } from './widgetData'
import type { ChoreDay } from './reminderPlans'
import KinwallNative from '../modules/kinwall-native'

// Android home-screen widgets, rendered from JavaScript in a headless task
// (react-native-android-widget), so they reuse the API client and the widgets' key (app.json lists
// them): Kinwall (now and next, chores left), Chores (tap to tick), List (Groceries or a chosen
// list; tap to tick, Add opens the app) and Take now (how many medicines are due, never which).
// Colors: the family's (src/appearance.ts widgetPalette), light and dark, so Android picks the one
// that matches its dark theme. Taps open the app through the same links the iOS widgets use.
// Home Screen only: the library declares every widget `home_screen`, never `keyguard`, so none of
// them (Take now above all) can go on the Lock Screen or the Android 16 hub.

type Name = 'Kinwall' | 'Chores' | 'List' | 'TakeNow'
const link = (to: string) => ({ uri: `family.kinwall.app:/open?to=${to}` })
const time = (iso: string) => new Date(iso).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
const DEMO_FLAG = 'family.kinwall.demo'

// ---- Each widget's own setting (the person, the list), chosen in its configuration screen ----

type Config = { member?: string | null; list?: string }
const configKey = (id: number) => `widget.${id}`
const loadConfig = (id: number): Config => { try { return JSON.parse(SecureStore.getItem(configKey(id)) ?? '{}') } catch { return {} } }
const saveConfig = (id: number, c: Config) => SecureStore.setItemAsync(configKey(id), JSON.stringify(c)).catch(() => {})

// ---- Drawing ----

function Frame({ p, children, to }: { p: WidgetPalette; children: React.ReactNode; to?: string }) {
  return (
    <FlexWidget style={{ height: 'match_parent', width: 'match_parent', flexDirection: 'column', backgroundColor: p.bg, borderRadius: 16, padding: 14 }}
      clickAction={to ? 'OPEN_URI' : 'OPEN_APP'} clickActionData={to ? link(to) : undefined}>
      {children}
    </FlexWidget>
  )
}
const Label = ({ p, text }: { p: WidgetPalette; text: string }) => <TextWidget text={text} style={{ fontSize: 11, fontWeight: '900', color: p.accent }} />
const Note = ({ p, text }: { p: WidgetPalette; text: string }) => <TextWidget text={text} style={{ fontSize: 13, color: p.dim }} />

function NowAndNext({ p, b, problem }: { p: WidgetPalette; b: Board | null; problem?: string }) {
  const { now, next } = b ? nowAndNext(b) : {}
  const remaining = b?.chores.reduce((n, c) => n + c.remaining, 0) ?? 0
  const total = b?.chores.reduce((n, c) => n + c.total, 0) ?? 0
  const row = (label: string, title: string, sub: string, to: string) => (
    <FlexWidget style={{ flexDirection: 'column', marginBottom: 6 }} clickAction="OPEN_URI" clickActionData={link(to)}>
      <Label p={p} text={label} />
      <TextWidget text={title} style={{ fontSize: 15, fontWeight: 'bold', color: p.fg }} maxLines={2} />
      <TextWidget text={sub} style={{ fontSize: 12, color: p.dim }} />
    </FlexWidget>
  )
  return (
    <Frame p={p}>
      {problem ? <Note p={p} text={problem} /> : null}
      {now ? row('NOW', now.title, `ends ${time(now.end)}`, 'calendar') : null}
      {next ? row('NEXT', next.title, next.leaveAt && Date.parse(next.leaveAt) > Date.now() ? `🚗 leave ${time(next.leaveAt)} · ${time(next.start)}` : time(next.start), 'calendar') : null}
      {b && !now && !next ? row('TODAY', 'Nothing more today', 'Enjoy the evening.', 'calendar') : null}
      {total > 0 ? row('CHORES', remaining === 0 ? 'Chores done 🎉' : `${remaining} of ${total} left`, 'Tap to tick them off', 'chores') : null}
    </Frame>
  )
}

type ChoresData = { date: string; person: string | null; names: Record<string, string>; chores: ChoreDay[]; demo?: boolean }
function Chores({ p, d, problem }: { p: WidgetPalette; d: ChoresData | null; problem?: string }) {
  const rows = d ? choreRows(d.chores, d.person) : []
  const left = rows.filter((c) => !isTicked(c)).length
  const title = d?.person ? `${d.names[d.person] ?? 'My'} chores` : 'Chores'
  return (
    <Frame p={p} to="chores">
      <Label p={p} text={d ? `${title.toUpperCase()} · ${left === 0 ? 'ALL DONE 🎉' : `${left} LEFT`}` : 'CHORES'} />
      {problem ? <Note p={p} text={problem} /> : null}
      {d ? (
        <ListWidget style={{ height: 'match_parent', width: 'match_parent', marginTop: 6 }}>
          {rows.map((c) => {
            const tap = choreTap(c, d.person)
            const click = d.demo || !tap.tick ? { clickAction: 'OPEN_URI', clickActionData: link(d.demo ? 'chores' : tap.tick ? 'chores' : tap.open) }
              : { clickAction: 'CHORE', clickActionData: { id: c.id, date: d.date, memberId: tap.memberId } }
            const who = !d.person && c.memberId ? ` · ${d.names[c.memberId] ?? ''}` : !d.person ? ' · Anyone' : ''
            return (
              <FlexWidget key={c.id} style={{ width: 'match_parent', flexDirection: 'row', alignItems: 'center', backgroundColor: p.card, borderRadius: 10, padding: 8, marginBottom: 4 }} {...click}>
                <TextWidget text={isTicked(c) ? '✅' : (c.emoji ?? '⬜️')} style={{ fontSize: 16, marginRight: 8 }} />
                <TextWidget text={`${c.title}${who}`} style={{ fontSize: 14, color: isTicked(c) ? p.dim : p.fg }} maxLines={1} truncate="END" />
              </FlexWidget>
            )
          })}
        </ListWidget>
      ) : null}
    </Frame>
  )
}

function List({ p, d, problem, demo, off }: { p: WidgetPalette; d: ListDetail | null; problem?: string; demo?: boolean; off?: boolean }) {
  const open = d?.items.filter((i) => !i.done) ?? []
  const to = d ? `lists&list=${d.list.id}` : 'lists'
  return (
    <Frame p={p} to={to}>
      <FlexWidget style={{ width: 'match_parent', flexDirection: 'row', alignItems: 'center' }}>
        <FlexWidget style={{ flex: 1, flexDirection: 'column' }}>
          <TextWidget text={d ? `${d.list.emoji ? d.list.emoji + ' ' : ''}${d.list.name}` : 'List'} style={{ fontSize: 15, fontWeight: 'bold', color: p.fg }} maxLines={1} truncate="END" />
          <TextWidget text={d ? (open.length === 0 ? 'All done' : `${open.length} left`) : ''} style={{ fontSize: 12, color: p.dim }} />
        </FlexWidget>
        {/* A widget can't take typing: Add opens the list, where the add field is. Not with Lists off. */}
        {off ? null : (
          <FlexWidget style={{ backgroundColor: p.accent, borderRadius: 14, paddingHorizontal: 12, paddingVertical: 6 }} clickAction="OPEN_URI" clickActionData={link(to)}>
            <TextWidget text="+ Add" style={{ fontSize: 13, fontWeight: 'bold', color: p.bg }} />
          </FlexWidget>
        )}
      </FlexWidget>
      {problem ? <Note p={p} text={problem} /> : null}
      {d ? (
        <ListWidget style={{ height: 'match_parent', width: 'match_parent', marginTop: 8 }}>
          {open.map((i) => (
            <FlexWidget key={i.id} style={{ width: 'match_parent', flexDirection: 'row', alignItems: 'center', backgroundColor: p.card, borderRadius: 10, padding: 8, marginBottom: 4 }}
              {...(demo ? { clickAction: 'OPEN_URI', clickActionData: link(to) } : { clickAction: 'ITEM', clickActionData: { listId: d.list.id, id: i.id } })}>
              <TextWidget text="⬜️" style={{ fontSize: 16, marginRight: 8 }} />
              <TextWidget text={i.quantity ? `${i.title} · ${i.quantity}` : i.title} style={{ fontSize: 14, color: p.fg }} maxLines={1} truncate="END" />
            </FlexWidget>
          ))}
        </ListWidget>
      ) : null}
    </Frame>
  )
}

function TakeNow({ p, due, problem }: { p: WidgetPalette; due: number | null; problem?: string }) {
  return (
    <Frame p={p} to="calendar">
      <Label p={p} text="MEDICINE" />
      {problem ? <Note p={p} text={problem} /> : (
        <FlexWidget style={{ flexDirection: 'column', marginTop: 4 }}>
          <TextWidget text={due ? `💊 ${due}` : '💊'} style={{ fontSize: 28, fontWeight: 'bold', color: p.fg }} />
          <TextWidget text={takeNowText(due ?? 0)} style={{ fontSize: 13, color: p.dim }} />
        </FlexWidget>
      )}
    </Frame>
  )
}

// ---- Data ----

/** While the demo is open (its flag, src/demo.ts), the widgets show the demo family, like the iOS
 * widgets' built-in data; a real family's key always wins. */
function sampleBoard(now = Date.now()): Board {
  const at = (min: number) => new Date(now + min * 60_000).toISOString()
  const today = 'demo'
  return {
    today,
    events: [
      { id: 'reading', title: 'Reading Time', start: at(-15), end: at(30), allDay: false, date: today },
      { id: 'piano', title: 'Piano Lesson', start: at(70), end: at(115), leaveAt: at(45), allDay: false, date: today },
    ],
    chores: [
      { memberId: 'maya', name: 'Maya', avatar: null, remaining: 1, total: 3 },
      { memberId: 'leo', name: 'Leo', avatar: null, remaining: 2, total: 4 },
    ],
  }
}

const OFFLINE = "Can't reach Kinwall right now"
const SIGNED_OUT = 'Open Kinwall to sign in'
const CHORES_OFF = 'Chores are turned off in Kinwall'
const LISTS_OFF = 'Lists are turned off in Kinwall'
const MEDICINE_OFF = 'Medicine is turned off in Kinwall'
const ownPerson = (c: Connection) => me(c).then((m) => (m.owner && m.owner !== 'shared' ? m.owner : null)).catch(() => null)

/** Fetches once; draws with either palette. */
async function draw(name: Name, id: number, problem?: string): Promise<(p: WidgetPalette) => React.JSX.Element> {
  const c = await widgetConnection()
  const demo = !c && !!(await KinwallNative?.keychainGet(DEMO_FLAG, true).catch(() => null))
  switch (name) {
    case 'Chores': {
      if (demo) return (p) => <Chores p={p} d={{ date: 'demo', person: null, names: DEMO_PEOPLE, chores: DEMO_CHORES, demo }} problem="Demo" />
      if (!c) return (p) => <Chores p={p} d={null} problem={SIGNED_OUT} />
      const [b, f] = await Promise.all([board(c, 1).catch(() => null), features(c)])
      if (f.chores === false) return (p) => <Chores p={p} d={null} problem={CHORES_OFF} />
      const chores = b && (await choresOn(c, b.today).catch(() => null))
      if (!b || !chores) return (p) => <Chores p={p} d={null} problem={OFFLINE} />
      const set = loadConfig(id)
      const person = set.member !== undefined ? set.member : await ownPerson(c)
      const names = Object.fromEntries(b.chores.filter((x) => x.memberId).map((x) => [x.memberId!, x.name ?? '']))
      return (p) => <Chores p={p} d={{ date: b.today, person, names, chores }} problem={problem} />
    }
    case 'List': {
      if (demo) return (p) => <List p={p} d={DEMO_GROCERIES} problem="Demo" demo />
      if (!c) return (p) => <List p={p} d={null} problem={SIGNED_OUT} />
      if ((await features(c)).lists === false) return (p) => <List p={p} d={null} problem={LISTS_OFF} off />
      const chosen = loadConfig(id).list ?? (await lists(c).then(pickGroceries).catch(() => null))?.id
      const d = chosen ? await list(c, chosen).catch(() => null) : null
      return (p) => <List p={p} d={d} problem={d ? problem : OFFLINE} />
    }
    case 'TakeNow': {
      if (demo) return (p) => <TakeNow p={p} due={1} />
      if (!c) return (p) => <TakeNow p={p} due={null} problem={SIGNED_OUT} />
      if (!medicinesOn(await settings(c))) return (p) => <TakeNow p={p} due={null} problem={MEDICINE_OFF} />
      // An older server with medicines off (404): nothing due.
      const due = await dueDoses(c).then((r) => r.doses.length, (e) => (e?.status === 404 ? 0 : null))
      return (p) => <TakeNow p={p} due={due} problem={due == null ? OFFLINE : undefined} />
    }
    default: {
      if (demo) return (p) => <NowAndNext p={p} b={sampleBoard()} problem="Demo" />
      if (!c) return (p) => <NowAndNext p={p} b={null} problem={SIGNED_OUT} />
      const [fetched, f] = await Promise.all([board(c, 1).catch(() => null), features(c)])
      const b = fetched && f.chores === false ? { ...fetched, chores: [] } : fetched // no chores line with Chores off
      return (p) => <NowAndNext p={p} b={b} problem={b ? undefined : OFFLINE} />
    }
  }
}

/** Light and dark, so the widget follows Android's dark theme (or the family's fixed choice). */
async function render(name: Name, id: number, problem?: string): Promise<WidgetRepresentation> {
  const a = savedAppearance()
  const widget = await draw(name, id, problem)
  return { light: widget(widgetPalette(a, false)), dark: widget(widgetPalette(a, true)) }
}

/** A tick from a widget: saved with the widgets' key, then every widget redraws (the Kinwall one
 * counts chores too). Offline or refused, the row stays and the widget says so. */
async function click(props: WidgetTaskHandlerProps): Promise<string | undefined> {
  const d = (props.clickActionData ?? {}) as Record<string, string | null>
  const c = await widgetConnection()
  if (!c) return SIGNED_OUT
  const saved = props.clickAction === 'CHORE' ? await completeChore(c, d.id!, d.date!, d.memberId ?? null).then(() => true, () => false)
    : props.clickAction === 'ITEM' ? await setItemDone(c, d.listId!, d.id!, true).then(() => true, () => false)
    : true
  return saved ? undefined : "Didn't save. Try again, or open Kinwall."
}

/** Every widget redraws (modules/kinwall-native/android Widgets.kt sends Android's own update). */
export const reloadWidgets = () => { KinwallNative?.reloadWidgets() }

export function registerWidgets() {
  registerWidgetTaskHandler(async (props: WidgetTaskHandlerProps) => {
    const { widgetName, widgetId } = props.widgetInfo
    if (props.widgetAction === 'WIDGET_DELETED') { SecureStore.deleteItemAsync(configKey(widgetId)).catch(() => {}); return }
    const problem = props.widgetAction === 'WIDGET_CLICK' ? await click(props) : undefined
    props.renderWidget(await render(widgetName as Name, widgetId, problem))
    if (props.widgetAction === 'WIDGET_CLICK' && !problem) KinwallNative?.reloadWidgets()
  })
  registerWidgetConfigurationScreen(Configure)
}

// ---- The Chores and List widgets' settings (long-press the widget → its settings) ----

function Configure({ widgetInfo, renderWidget, setResult }: WidgetConfigurationScreenProps) {
  const ui = useUi()
  const [options, setOptions] = useState<{ id: string | null; label: string }[] | null>(null)
  const chores = widgetInfo.widgetName === 'Chores'
  useEffect(() => {
    widgetConnection().then(async (c) => {
      if (!c) return setOptions([])
      if (chores) setOptions([{ id: null, label: 'Everyone' }, ...(await members(c).catch(() => [])).map((m) => ({ id: m.id, label: `${m.avatar ? m.avatar + ' ' : ''}${m.name}` }))])
      else setOptions((await lists(c).catch(() => [])).filter((l) => !l.archived).map((l) => ({ id: l.id, label: `${l.emoji ? l.emoji + ' ' : ''}${l.name}` })))
    })
  }, [chores])
  const pick = async (id: string | null) => {
    await saveConfig(widgetInfo.widgetId, chores ? { member: id } : { list: id ?? undefined })
    renderWidget(await render(widgetInfo.widgetName as Name, widgetInfo.widgetId))
    setResult('ok')
  }
  return (
    <SafeAreaView style={ui.root}>
      <ScrollView contentContainerStyle={[ui.screen, { justifyContent: 'flex-start' }]}>
        <Text style={ui.title}>{chores ? 'Whose chores?' : 'Which list?'}</Text>
        {options === null ? null : options.length === 0 ? <Text style={ui.muted}>{SIGNED_OUT}, then try again.</Text> : options.map((o) => (
          <Pressable key={o.id ?? 'everyone'} style={[ui.button, ui.secondary]} onPress={() => pick(o.id)}><Text style={ui.secondaryText}>{o.label}</Text></Pressable>
        ))}
        <Pressable onPress={() => setResult('cancel')}><Text style={ui.link}>Cancel</Text></Pressable>
      </ScrollView>
    </SafeAreaView>
  )
}
