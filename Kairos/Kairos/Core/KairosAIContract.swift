import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct KairosAIServiceError: LocalizedError {
    let status: Int
    let code: String?
    let resetsAt: String?
    let message: String
    nonisolated var errorDescription: String? { message }
}

enum KairosAIContract {
    nonisolated static func request(messages: [[String: String]], idToken: String, appCheckToken: String) throws -> URLRequest {
        guard !idToken.isEmpty, !appCheckToken.isEmpty else {
            throw KairosAIServiceError(status: 401, code: "credentials", resetsAt: nil, message: "Sign in again and retry. Kairos could not verify this app session.")
        }
        guard !messages.isEmpty, messages.count <= 40,
              messages.allSatisfy({ ["system", "user", "assistant"].contains($0["role"] ?? "") && !($0["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw KairosAIServiceError(status: 400, code: nil, resetsAt: nil, message: "This conversation cannot be sent. Start a new chat and try again.")
        }
        let body = try JSONSerialization.data(withJSONObject: ["messages": messages])
        guard body.count <= 128 * 1024 else {
            throw KairosAIServiceError(status: 413, code: nil, resetsAt: nil, message: "This conversation is too long. Start a new chat or shorten your message.")
        }
        var request = URLRequest(url: URL(string: "https://kairos-web.kirosapp.workers.dev/api/ai")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 100
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue(appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")
        request.httpBody = body
        return request
    }

    nonisolated static func response(data: Data, status: Int) throws -> String {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200 else {
            throw KairosAIServiceError(status: status, code: root?["code"] as? String, resetsAt: root?["resetsAt"] as? String,
                message: (root?["error"] as? String).map { String($0.prefix(500)) } ?? "Kairos AI is temporarily unavailable. Please try again later.")
        }
        guard let choices = root?["choices"] as? [[String: Any]],
              choices.first?["finish_reason"] as? String != "length",
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KairosAIServiceError(status: 502, code: nil, resetsAt: nil, message: "Kairos AI could not finish its response. Try a shorter request.")
        }
        return content
    }
}
