import Foundation

@main struct Checks {
 @MainActor static func main() async throws {
  let queue=EventActivityCoordinator()
  var active=0,maximum=0
  var completed=[Int]()
  var tasks=[Task<Void,Error>]()
  for i in 0..<20 {
   tasks.append(Task { @MainActor in
    try await queue.perform {
     active += 1; maximum=max(maximum,active)
     try await Task.sleep(nanoseconds: 1_000_000)
     completed.append(i);active -= 1
    }
   })
  }
  for task in tasks {try await task.value}
  precondition(maximum==1,"Only one event start/cleanup may run across suspension points")
  precondition(completed.count==20)
  enum Expected:Error {case failed}
  do {try await queue.perform {throw Expected.failed};preconditionFailure("must throw")}catch Expected.failed{}
  try await queue.perform {completed.append(20)}
  precondition(completed.last==20,"A failed update cannot block later cleanup")
  let a=EventActivityCoordinator.Candidate(id:"local",activity:"event:soccer",running:true)
  let b=EventActivityCoordinator.Candidate(id:"remote",activity:"event:soccer",running:true)
  let ended=EventActivityCoordinator.Candidate(id:"a-ended",activity:"event:soccer",running:false)
  precondition(EventActivityCoordinator.keeper([b,ended,a],preferred:"event:soccer")=="local")
  precondition(EventActivityCoordinator.keeper([a,b,ended],preferred:"event:soccer")=="local","Order must not change the survivor")
  let next=EventActivityCoordinator.Candidate(id:"next",activity:"event:piano",running:true)
  precondition(EventActivityCoordinator.keeper([a,b,next],preferred:"event:piano")=="next")
  precondition(EventActivityCoordinator.keeper([ended,next],preferred:"event:soccer")=="next","A late callback for an ended event must not close the current event")
  precondition(EventActivityCoordinator.keeper([ended],preferred:nil)==nil,"An ended Lock Screen card cannot survive")
  print("event activity checks passed")
 }
}
