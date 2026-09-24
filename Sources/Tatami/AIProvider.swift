import Foundation
import Security
import TatamiCore

struct AIPreset: Identifiable, Hashable {
    enum Format { case anthropic, openAI }
    let id: String
    let name: String
    let format: Format
    let baseURL: String
    let defaultModel: String?
    let needsKey: Bool
    let isLocal: Bool

    static let all: [AIPreset] = [
        AIPreset(id: "anthropic", name: "Anthropic", format: .anthropic, baseURL: "https://api.anthropic.com/v1", defaultModel: "claude-haiku-4-5", needsKey: true, isLocal: false),
        AIPreset(id: "openai", name: "OpenAI", format: .openAI, baseURL: "https://api.openai.com/v1", defaultModel: nil, needsKey: true, isLocal: false),
        AIPreset(id: "gemini", name: "Google Gemini", format: .openAI, baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", defaultModel: nil, needsKey: true, isLocal: false),
        AIPreset(id: "deepseek", name: "DeepSeek", format: .openAI, baseURL: "https://api.deepseek.com/v1", defaultModel: nil, needsKey: true, isLocal: false),
        AIPreset(id: "openrouter", name: "OpenRouter", format: .openAI, baseURL: "https://openrouter.ai/api/v1", defaultModel: nil, needsKey: true, isLocal: false),
        AIPreset(id: "ollama", name: "Ollama (this Mac)", format: .openAI, baseURL: "http://localhost:11434/v1", defaultModel: nil, needsKey: false, isLocal: true),
        AIPreset(id: "lmstudio", name: "LM Studio (this Mac)", format: .openAI, baseURL: "http://localhost:1234/v1", defaultModel: nil, needsKey: false, isLocal: true),
        AIPreset(id: "custom", name: "Custom (OpenAI-compatible)", format: .openAI, baseURL: "", defaultModel: nil, needsKey: false, isLocal: false),
    ]
    static func find(_ id: String) -> AIPreset { all.first { $0.id == id } ?? all[0] }

    func resolvedBaseURL(_ config: AIConfig) -> String { id == "custom" ? config.customBaseURL : baseURL }
    /// A custom endpoint on localhost counts as local: no cloud disclosure needed.
    func isLocal(_ config: AIConfig) -> Bool {
        isLocal || (id == "custom" && URL(string: config.customBaseURL)?.scheme == "http")
    }
    func host(_ config: AIConfig) -> String { URL(string: resolvedBaseURL(config))?.host ?? "the configured endpoint" }
}

enum AIError: LocalizedError {
    case missingKey(String), missingModel, badEndpoint, badKey, rateLimited, unreachable(local: Bool), truncated, provider(Int, String)
    var errorDescription: String? {
        switch self {
        case .missingKey(let name): "Add your \(name) API key in Preferences → AI."
        case .missingModel: "Choose a model in Preferences → AI."
        case .badEndpoint: "The custom endpoint must use HTTPS, or HTTP on localhost."
        case .badKey: "The provider rejected the API key. Check it in Preferences → AI."
        case .rateLimited: "The provider is rate limiting requests. Try again in a moment."
        case .unreachable(let local): local ? "Could not reach the local model server. Make sure it is running." : "Could not reach the provider. Check your internet connection."
        case .truncated: "The model's reply was cut off. Try a simpler request."
        case .provider(let status, let message): "The provider returned an error (\(status)): \(message)"
        }
    }
}

/// Requests go directly from this Mac to the selected provider (PRD AIO-08).
enum AIClient {
    static let timeout: TimeInterval = 60
    static let maxTokens = 8192

    static func complete(preset: AIPreset, config: AIConfig, model: String, key: String?, system: String, user: String) async throws -> String {
        let body: [String: Any]
        switch preset.format {
        case .anthropic:
            body = ["model": model, "max_tokens": maxTokens, "system": system, "messages": [["role": "user", "content": user]]]
        case .openAI:
            body = ["model": model, "max_tokens": maxTokens, "messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
        }
        let path = preset.format == .anthropic ? "messages" : "chat/completions"
        let json = try await send(preset: preset, config: config, key: key, path: path, body: body)
        switch preset.format {
        case .anthropic:
            if json["stop_reason"] as? String == "max_tokens" { throw AIError.truncated }
            let blocks = json["content"] as? [[String: Any]] ?? []
            return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        case .openAI:
            let choice = (json["choices"] as? [[String: Any]])?.first
            if choice?["finish_reason"] as? String == "length" { throw AIError.truncated }
            return (choice?["message"] as? [String: Any])?["content"] as? String ?? ""
        }
    }

    /// Doubles as Test Connection: it authenticates without spending tokens.
    static func models(preset: AIPreset, config: AIConfig, key: String?) async throws -> [String] {
        let json = try await send(preset: preset, config: config, key: key, path: "models", body: nil)
        let data = json["data"] as? [[String: Any]] ?? []
        return data.compactMap { $0["id"] as? String }.map { $0.replacingOccurrences(of: "models/", with: "") }.sorted()
    }

    private static func send(preset: AIPreset, config: AIConfig, key: String?, path: String, body: [String: Any]?) async throws -> [String: Any] {
        let base = preset.resolvedBaseURL(config)
        guard AIConfig.acceptableBaseURL(base), let url = URL(string: base.hasSuffix("/") ? base + path : base + "/" + path) else { throw AIError.badEndpoint }
        let key = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if preset.needsKey && key.isEmpty { throw AIError.missingKey(preset.name) }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch preset.format {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openAI:
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request, delegate: RejectRedirects.shared) }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch is URLError { throw AIError.unreachable(local: preset.isLocal(config)) }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (300..<400).contains(status) { throw AIError.provider(status, "The endpoint tried to redirect. Tatami only sends keys to the configured host.") }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        switch status {
        case 200..<300: return json
        case 401, 403: throw AIError.badKey
        case 429: throw AIError.rateLimited
        default:
            // Both formats use {"error": {"message": ...}}; cap length so a proxy HTML page doesn't flood the UI.
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? HTTPURLResponse.localizedString(forStatusCode: status)
            throw AIError.provider(status, String(message.prefix(300)))
        }
    }
}

/// Keys are attached per request, so a redirect would replay them to whatever host the server names.
final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    static let shared = RejectRedirects()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? { nil }
}

/// API keys, one Keychain item per preset. Never written to workspace.json, exports, or logs.
enum KeychainStore {
    private static let service = "app.tatami.mac.ai"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func read(_ account: String) -> String? {
        var item: CFTypeRef?
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Empty value deletes the item.
    static func save(_ value: String, account: String) throws {
        SecItemDelete(query(account) as CFDictionary)
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Could not save the key to the Keychain (\(status))."]) }
    }
}
