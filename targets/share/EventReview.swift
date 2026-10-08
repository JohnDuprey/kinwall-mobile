import KinwallKit
import SwiftUI

/// An event the share sheet read (ShareViewController.checkEvent), to fix and add to a calendar right
/// here: its title, date, all day or its times, place and notes, then the family's calendars this phone can
/// add to (the first is the family's default calendar for new events). Add to calendar saves it (POST
/// api/share with save). (A share extension can't open its app, so there's no Open in Kinwall here.)
/// The pickers hold the household's wall-clock time as UTC (Share.pickerDate), so nothing shifts
/// with the phone's own time zone.
struct EventReview: View {
  let guessed: Bool
  let calendars: [Share.FamilyCalendar]
  /// Saves it: an error line to show, or nil once it's saved (the sheet moves on).
  let add: (Share.EventDraft, String) async -> String?
  let notEvent: () -> Void
  let cancel: () -> Void

  @State private var title: String
  @State private var place: String
  @State private var notes: String
  @State private var day: Date
  @State private var start: Date
  @State private var end: Date
  @State private var allDay: Bool
  @State private var calendarId: String
  @State private var working = false
  @State private var error: String?

  /// minutes: how long a new event lasts with no end read (the family's setting).
  init(draft: Share.EventDraft, guessed: Bool, calendars: [Share.FamilyCalendar], minutes: Int = 60, add: @escaping (Share.EventDraft, String) async -> String?,
       notEvent: @escaping () -> Void, cancel: @escaping () -> Void) {
    self.guessed = guessed
    self.calendars = calendars
    self.add = add
    self.notEvent = notEvent
    self.cancel = cancel
    // No date read: today, on this phone, for the person to change.
    let today = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: .now) }()
    let date = draft.date ?? today
    let start = Share.pickerDate(date, draft.time ?? "09:00")!
    _title = State(initialValue: draft.title ?? "")
    _place = State(initialValue: draft.place ?? "")
    _notes = State(initialValue: draft.notes ?? "")
    _day = State(initialValue: Share.pickerDate(date)!)
    _start = State(initialValue: start)
    _end = State(initialValue: draft.end.flatMap { Share.pickerDate(date, $0) } ?? start.addingTimeInterval(Double(minutes * 60)))
    _allDay = State(initialValue: draft.time == nil)
    _calendarId = State(initialValue: calendars.first?.id ?? "")
  }

  private var draft: Share.EventDraft { Share.draft(title: title, place: place, notes: notes, day: day, start: start, end: end, allDay: allDay) }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          labeled("Title") { TextField("Title", text: $title) }
          DatePicker("Date", selection: $day, displayedComponents: .date)
          Toggle("All day", isOn: $allDay)
          if !allDay {
            DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
            DatePicker("Ends", selection: $end, displayedComponents: .hourAndMinute)
          }
          labeled("Place") { TextField("Place", text: $place, axis: .vertical).lineLimit(1...3) }
          labeled("Notes") { TextField("What to bring, how to RSVP", text: $notes, axis: .vertical).lineLimit(2...6) }
        }
        if let error { Section { Text(error).foregroundStyle(.red) } }
      }
      .environment(\.timeZone, Share.utc)
      .disabled(working)
      .onChange(of: start) { old, new in
        // Moving the start keeps the length (the family's default until the end is changed), so the
        // end never lands before it.
        end = new.addingTimeInterval(max(end.timeIntervalSince(old), 15 * 60))
      }
      .safeAreaInset(edge: .bottom) { buttons }
      .navigationTitle(guessed ? "Looks like an event" : "Check the event")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: cancel) { Image(systemName: "xmark") }.accessibilityLabel("Cancel").disabled(working)
        }
      }
    }
  }

  private var buttons: some View {
    VStack(spacing: 4) {
      if !calendars.isEmpty {
        // Right above Add, so which calendar it goes to is always in view (the form scrolls under it).
        HStack {
          Text("Calendar").foregroundStyle(.secondary)
          Spacer()
          Picker("Calendar", selection: $calendarId) { ForEach(calendars) { Text($0.name).tag($0.id) } }
            .pickerStyle(.menu)
        }
        .frame(minHeight: 44)
        Button {
          Task { working = true; error = await add(draft, calendarId); working = false }
        } label: {
          Group { if working { ProgressView() } else { Text("Add to calendar").bold() } }.frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.kinwallAction)
        .foregroundStyle(.white)
        .disabled(working || draft.title == nil)
      }
      if guessed { Button(action: notEvent) { Text(Share.notLabel(.event)).frame(maxWidth: .infinity, minHeight: 44) }.disabled(working) }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.bar)
  }

  /// A field with its name above it, so the name stays once it's filled in.
  private func labeled(_ name: String, @ViewBuilder field: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(name).font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
      field()
    }
  }
}
