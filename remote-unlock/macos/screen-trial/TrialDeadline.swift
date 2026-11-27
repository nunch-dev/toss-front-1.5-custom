import Foundation

struct TrialDeadline: Codable {
    let expiresAt: TimeInterval
    let startedUptime: TimeInterval

    init(wallTime: TimeInterval, uptime: TimeInterval) {
        expiresAt = wallTime + 180
        startedUptime = uptime
    }

    func elapsed(wallTime: TimeInterval, uptime: TimeInterval) -> Bool {
        // A wall-clock correction must not extend the trial. A reboot resets uptime.
        wallTime >= expiresAt || uptime < startedUptime || uptime >= startedUptime + 180
    }
}
