import Cocoa

// MARK: - Conversation message model

struct ChatMessage {
    let role: String    // "user" or "assistant"
    let content: String
}

// MARK: - AIManager

final class AIManager {

    static let shared = AIManager()
    private init() {}

    private let serverURL = Config.serverURL
    var licenseKey: String = ""
    var conversationHistory: [ChatMessage] = []

    private var activeSession: URLSession?

    func clearHistory() {
        conversationHistory = []
    }

    // MARK: - Query with streaming

    func query(image: NSImage?,
               prompt: String = "Answer this.",
               onChunk: @escaping (String) -> Void,
               onComplete: @escaping (String) -> Void,
               onError: @escaping (String) -> Void) {

        guard !licenseKey.isEmpty else {
            onError("No license key")
            return
        }
        guard let url = URL(string: "\(serverURL)/query") else {
            onError("Invalid server URL")
            return
        }

        let provider = UserDefaults.standard.string(forKey: "ai_provider") ?? "openai"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        var body: [String: Any] = [
            "licenseKey": licenseKey,
            "provider": provider,
            "prompt": prompt
        ]

        if let image = image, let base64 = imageToBase64(image) {
            body["image"] = base64
        }

        if !conversationHistory.isEmpty {
            let historyArray = conversationHistory.map { ["role": $0.role, "content": $0.content] }
            body["messages"] = historyArray
        }

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
    var onComplete: (String) -> Void
    var onError: (String) -> Void
    var buffer = ""
    var fullResponse = ""
    var didFireComplete = false

    init(onChunk: @escaping (String) -> Void,
         onComplete: @escaping (String) -> Void,
         onError: @escaping (String) -> Void) {
        self.onChunk = onChunk
        self.onComplete = onComplete
        self.onError = onError
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }


        // Handle raw JSON error responses (non-SSE, e.g. 401/402 before SSE headers)
        if text.hasPrefix("{"), let jsonData = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let error = json["error"] as? String {
            DispatchQueue.main.async { self.onError(error) }
            return
        }

        buffer += text

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
                fullResponse += chunk
                DispatchQueue.main.async { self.onChunk(chunk) }
            } else if let done = json["done"] as? Bool, done {
                let full = json["fullText"] as? String ?? fullResponse
                didFireComplete = true
                DispatchQueue.main.async { self.onComplete(full) }
            } else if let error = json["error"] as? String {
                DispatchQueue.main.async { self.onError(error) }
            }
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                self.onError(error.localizedDescription)
            } else if !self.didFireComplete && !self.fullResponse.isEmpty {
                self.onComplete(self.fullResponse)
            }
        }
    }
}
