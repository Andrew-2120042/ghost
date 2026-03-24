import IOKit
import Foundation

final class DeviceManager {
    static let shared = DeviceManager()
    private init() {}

    var deviceHash: String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { IOObjectRelease(service) }

        let uuid = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String ?? "unknown"

        let data = Data(uuid.utf8)
        return data.map { String(format: "%02x", $0) }.joined()
    }
}
