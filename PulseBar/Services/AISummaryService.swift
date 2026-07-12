import Foundation

/// Optional natural-language interpretation of a storage scan, via a cheap LLM
/// (Anthropic Haiku). Off by default; requires the user's own API key (stored in
/// the Keychain). Sends only an **aggregated** summary — category names + sizes,
/// abbreviated folder paths, and the deterministic insight titles — never a full
/// file listing. The user is told exactly what's sent before enabling.
actor AISummaryService {
    static let keychainAccount = "anthropic-api-key"

    /// Cheapest current model — this is a short, low-stakes summarization task.
    private let model = "claude-haiku-4-5"
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    enum ServiceError: LocalizedError {
        case missingKey
        case http(Int, String)
        case decoding
        case empty

        var errorDescription: String? {
            switch self {
            case .missingKey:      return "No API key set. Add your Anthropic API key to use AI insights."
            case .http(let code, let msg): return "Request failed (\(code)): \(msg)"
            case .decoding:        return "Couldn't read the AI response."
            case .empty:           return "The AI returned an empty response."
            }
        }
    }

    /// Builds a compact, privacy-conscious summary and returns Haiku's plain-English
    /// interpretation. `key` is passed in (read from the Keychain by the caller).
    func interpret(insights: [StorageInsight],
                   categories: [CategorySummary],
                   folders: [FolderAggregate],
                   diskFreeBytes: UInt64,
                   diskTotalBytes: UInt64,
                   key: String) async throws -> String {
        guard !key.isEmpty else { throw ServiceError.missingKey }

        let userContent = buildSummary(insights: insights, categories: categories,
                                       folders: folders,
                                       diskFreeBytes: diskFreeBytes, diskTotalBytes: diskTotalBytes)

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 600,
            "system": Self.systemPrompt,
            "messages": [
                ["role": "user", "content": userContent],
            ],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.extractError(from: data) ?? "unexpected error"
            throw ServiceError.http(http.statusCode, message)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw ServiceError.decoding
        }
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ServiceError.empty }
        return text
    }

    // MARK: - Prompt construction

    private static let systemPrompt = """
    You are a friendly macOS storage assistant helping a developer who is not a \
    cleanup expert. You are given an aggregated summary of a disk scan (category \
    totals, top folders with abbreviated paths, and a few pre-computed insights). \
    Write a short, concrete interpretation: what's taking space, what is safe to \
    clean vs. what to keep, and 2-4 specific next steps. Be plain-spoken and \
    reassuring. Never invent file paths or numbers beyond what's provided. Keep it \
    under 180 words. Use short paragraphs or a tight bullet list, no preamble.
    """

    private func buildSummary(insights: [StorageInsight],
                              categories: [CategorySummary],
                              folders: [FolderAggregate],
                              diskFreeBytes: UInt64, diskTotalBytes: UInt64) -> String {
        var lines: [String] = []
        lines.append("Disk: \(ByteFormatting.gigabytes(diskFreeBytes)) free of \(ByteFormatting.gigabytes(diskTotalBytes)).")

        if !categories.isEmpty {
            lines.append("\nCategories (name — size — items):")
            for c in categories.sorted(by: { $0.totalSizeBytes > $1.totalSizeBytes }).prefix(12) where c.totalSizeBytes > 0 {
                lines.append("- \(c.category.title): \(ByteFormatting.memory(c.totalSizeBytes)), \(c.itemCount) items")
            }
        }
        if !folders.isEmpty {
            lines.append("\nTop folders:")
            for f in folders.prefix(8) {
                lines.append("- \(f.displayPath): \(ByteFormatting.memory(f.sizeBytes)) (mostly \(f.dominantCategory.title))")
            }
        }
        if !insights.isEmpty {
            lines.append("\nPre-computed insights:")
            for i in insights.prefix(6) {
                lines.append("- \(i.title): \(i.detail)")
            }
        }
        lines.append("\nExplain this to me and tell me what to clean.")
        return lines.joined(separator: "\n")
    }

    private static func extractError(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else { return nil }
        return message
    }
}
