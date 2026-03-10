import Cocoa

final class AIManager {

    static let shared = AIManager()
    private init() {}

    private let serverURL = "http://localhost:3000"
    var licenseKey: String = ""

    private var activeSession: URLSession?

    // MARK: - Query with streaming

    func query(image: NSImage,
               onChunk: @escaping (String) -> Void,
               onComplete: @escaping () -> Void,
               onError: @escaping (String) -> Void) {

        print("Ghost: query() called")
        print("Ghost: licenseKey = '\(licenseKey)'")
        print("Ghost: serverURL = \(serverURL)")
        guard !licenseKey.isEmpty else {
            onError("No license key")
            return
        }
        guard let base64 = imageToBase64(image) else {
            onError("Could not encode image")
            return
        }
        guard let url = URL(string: "\(serverURL)/query") else {
            onError("Invalid server URL")
            return
        }

        print("Ghost: calling server at \(serverURL)/query")
        print("Ghost: license key = \(licenseKey)")
        print("Ghost: image base64 length = \(base64.count)")

        // Health check
        let healthURL = URL(string: "\(serverURL)/health")!
        URLSession.shared.dataTask(with: healthURL) { data, _, _ in
            if let data = data {
                print("Ghost: server health = \(String(data: data, encoding: .utf8) ?? "no response")")
            } else {
                print("Ghost: SERVER NOT REACHABLE")
            }
        }.resume()

        let provider = UserDefaults.standard.string(forKey: "ai_provider") ?? "openai"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "licenseKey": licenseKey,
            "image": base64,
            "provider": provider
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let delegate = SSEDelegate(onChunk: onChunk, onComplete: onComplete, onError: onError)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        activeSession = session
        session.dataTask(with: request).resume()
    }

    // MARK: - License validation

    func validateLicense(key: String,
                          completion: @escaping (Bool, Int, String?) -> Void) {
        guard let url = URL(string: "\(serverURL)/validate") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["licenseKey": key]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(false, 0, "Server unreachable") }
                return
            }
            let valid = json["valid"] as? Bool ?? false
            let queries = json["queriesRemaining"] as? Int ?? 0
            let error = json["error"] as? String
            DispatchQueue.main.async { completion(valid, queries, error) }
        }.resume()
    }

    // MARK: - Image encoding

    private func imageToBase64(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return pngData.base64EncodedString()
    }
}

// MARK: - SSE streaming delegate

private class SSEDelegate: NSObject, URLSessionDataDelegate {

    var onChunk: (String) -> Void
    var onComplete: () -> Void
    var onError: (String) -> Void
    var buffer = ""

    init(onChunk: @escaping (String) -> Void,
         onComplete: @escaping () -> Void,
         onError: @escaping (String) -> Void) {
        self.onChunk = onChunk
        self.onComplete = onComplete
        self.onError = onError
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        print("Ghost: raw server data = \(text)")

        // Handle raw JSON error responses (non-SSE, e.g. 401/402 before headers set)
        if text.hasPrefix("{"), let jsonData = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let error = json["error"] as? String {
            DispatchQueue.main.async { self.onError(error) }
            return
        }

        buffer += text

        // Process complete lines, keep last incomplete line in buffer
        let lines = buffer.components(separatedBy: "\n")
        buffer = lines.last ?? ""

        for line in lines.dropLast() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data: ") else { continue }

            let jsonStr = String(trimmed.dropFirst(6))
            guard jsonStr != "[DONE]" else { continue }

            guard let jsonData = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else { continue }

            if let chunk = json["text"] as? String {
                print("Ghost: chunk received = \(chunk)")
                DispatchQueue.main.async { self.onChunk(chunk) }
            } else if let error = json["error"] as? String {
                print("Ghost: server error = \(error)")
                DispatchQueue.main.async { self.onError(error) }
            }
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                print("Ghost: stream error = \(error.localizedDescription)")
                self.onError(error.localizedDescription)
            } else {
                print("Ghost: stream complete")
                self.onComplete()
            }
        }
    }
}
