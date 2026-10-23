import DeviceActivity
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) { RoutineEnforcement.expire() }
    override func intervalDidEnd(for activity: DeviceActivityName) { RoutineEnforcement.expire() }
}
