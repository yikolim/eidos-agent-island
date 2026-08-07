import Foundation
import IOKit.ps

/// Snapshot of the machine's power source, read from IOKit.
struct PowerSnapshot: Equatable {
    var batteryPercent: Int?     // nil on desktops with no battery
    var onACPower: Bool
    var isCharging: Bool

    var batteryText: String {
        guard let batteryPercent else { return "No battery" }
        return "\(batteryPercent)%"
    }
}

enum BatteryMonitor {
    static func read() -> PowerSnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            // No power source info (e.g. Mac mini / Mac Studio): treat as AC.
            return PowerSnapshot(batteryPercent: nil, onACPower: true, isCharging: false)
        }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = max > 0 ? Int((Double(current) / Double(max)) * 100.0) : 0
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false

            return PowerSnapshot(
                batteryPercent: percent,
                onACPower: state == kIOPSACPowerValue,
                isCharging: charging
            )
        }

        return PowerSnapshot(batteryPercent: nil, onACPower: true, isCharging: false)
    }
}
