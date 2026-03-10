import Cocoa
import CoreGraphics

final class ScreenCaptureManager {

    static func capture(
        region: NSRect,
        completion: @escaping (NSImage?) -> Void
    ) {
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let flippedY = screenHeight - region.origin.y - region.height
        let regionString = "\(Int(region.origin.x)),\(Int(flippedY)),\(Int(region.width)),\(Int(region.height))"
        let tempPath = "/tmp/ghost_capture.png"

        try? FileManager.default.removeItem(atPath: tempPath)

        let process = Process()
        process.launchPath = "/usr/sbin/screencapture"
        process.arguments = ["-x", "-R", regionString, tempPath]

        process.terminationHandler = { p in
            DispatchQueue.main.async {
                if p.terminationStatus != 0 {
                    print("Ghost: capture failed exit=\(p.terminationStatus)")
                    NotificationCenter.default.post(
                        name: NSNotification.Name("GhostDeactivate"),
                        object: nil
                    )
                    NotificationCenter.default.post(
                        name: NSNotification.Name("GhostNeedsScreenPermission"),
                        object: nil
                    )
                    completion(nil)
                    return
                }

                let image = NSImage(contentsOfFile: tempPath)
                completion(image)
            }
        }

        do {
            try process.run()
        } catch {
            print("Ghost: could not run screencapture: \(error)")
            DispatchQueue.main.async { completion(nil) }
        }
    }
}
