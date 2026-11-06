import Foundation
@main struct Checks {
 static func main() throws {
  let data = Data(#"{"timers":[{"id":1,"label":"Rice","seconds":60,"endsAt":61000,"done":false,"alarmTitle":"Time's up: Rice","alarmBody":"Timer","check":30,"checkTitle":"Check it: Rice"},{"id":2,"label":"Pasta","seconds":90,"endsAt":91000,"done":false,"alarmTitle":"Time's up: Pasta","alarmBody":"Timer"}]}"#.utf8)
  var state = CookingTimerState()
  try state.receive(data)
  precondition(state.change(id: 1, start: false, expectedEnd: 61000, expectedRevision: "", now: 21000))
  precondition(state.timers[0].left == 40000)
  precondition(!state.change(id: 1, start: false, expectedEnd: 61000, expectedRevision: "", now: 22000), "Double taps cannot toggle twice")
  let revision = state.timers[0].nativeRevision!
  try state.receive(data)
  precondition(state.timers[0].left == 40000, "Stale web payload cannot restart a paused timer")
  var payload = try JSONSerialization.jsonObject(with: state.payload()) as! [String: Any]
  precondition(payload["timerId"] as? Double == 1)
  precondition((payload["alarms"] as! [[String: Any]]).count == 1, "Only the other timer rings")
  precondition(state.change(id: 1, start: true, expectedEnd: 61000, expectedRevision: revision, now: 100000))
  precondition(state.timers[0].endsAt == 140000)
  payload = try JSONSerialization.jsonObject(with: state.payload()) as! [String: Any]
  let checks = payload["checks"] as! [[String: Any]]
  precondition(checks.first?["at"] as? Double == 110000, "A range's check shifts with resume")
  var acknowledged = try JSONSerialization.jsonObject(with: data) as! [String: Any]
  var acknowledgedTimers = acknowledged["timers"] as! [[String: Any]]
  acknowledgedTimers[0]["nativeRevision"] = state.timers[0].nativeRevision!
  acknowledgedTimers[0]["endsAt"] = 200000.0 // a later reset on the page wins after it saw the native revision
  acknowledged["timers"] = acknowledgedTimers
  try state.receive(JSONSerialization.data(withJSONObject: acknowledged))
  precondition(state.changes.isEmpty, "Echoed revisions acknowledge native changes")
  precondition(state.timers[0].endsAt == 200000, "A reset after acknowledgment wins")
  precondition(!state.change(id: 1, start: false, expectedEnd: 140000, expectedRevision: revision, now: 150000), "Old buttons cannot pause a reset timer")
  precondition(!state.change(id: 1, start: false, expectedEnd: 200000, expectedRevision: state.timers[0].nativeRevision!, now: 200001), "Expired timers cannot pause")
  try state.receive(data)
  precondition(state.timers[0].endsAt == 200000, "Delayed payloads cannot undo an acknowledged revision")
  let restored = try JSONDecoder().decode(CookingTimerState.self, from: JSONEncoder().encode(state))
  precondition(restored.timers[0].endsAt == 200000, "Survives process restart")
  try state.receive(Data(#"{"timers":[]}"#.utf8))
  precondition(state.changes.isEmpty, "Cancelled timers lose overrides")
  print("cooking timer checks passed")
 }
}
