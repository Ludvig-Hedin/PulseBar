import Foundation

/// Reports Docker reclaimable space without ever deleting anything itself.
/// `CleanupService` is responsible for triggering `docker system prune` when the
/// user opts in.
enum DockerProbe {
    struct Report {
        let reclaimableBytes: UInt64
        let imageCount: Int
        let containerCount: Int
        let volumeCount: Int
    }

    /// Runs `docker system df --format '{{json .}}'`. Returns `nil` if Docker isn't
    /// installed, the daemon isn't running, or output couldn't be parsed.
    static func read() -> Report? {
        let candidates = Locations.cliCandidates(for: .docker)
        guard let binary = CommandRunner.resolveBinary(candidates) else { return nil }

        let output: CommandRunner.Output
        do {
            output = try CommandRunner.run(
                launchPath: binary,
                arguments: ["system", "df", "--format", "{{json .}}"],
                timeout: 3
            )
        } catch {
            return nil
        }

        guard output.exitCode == 0 else { return nil }

        // `docker system df --format '{{json .}}'` emits one JSON object per line:
        // `{"Type":"Images","TotalCount":"12",...,"Reclaimable":"1.234GB (45%)"}`.
        var reclaimable: UInt64 = 0
        var images = 0, containers = 0, volumes = 0
        let lines = output.stdout.split(whereSeparator: { $0.isNewline })
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let type = (dict["Type"] as? String) ?? ""
            let reclaimStr = (dict["Reclaimable"] as? String) ?? ""
            let countStr = (dict["TotalCount"] as? String) ?? "0"
            let count = Int(countStr) ?? 0

            reclaimable &+= parseHumanSize(reclaimStr)
            switch type {
            case "Images":          images = count
            case "Containers":      containers = count
            case "Local Volumes":   volumes = count
            default:                break
            }
        }

        return Report(
            reclaimableBytes: reclaimable,
            imageCount: images,
            containerCount: containers,
            volumeCount: volumes
        )
    }

    /// Parses values like `"1.234GB (45%)"`, `"512MB"`, `"0B"` into bytes.
    /// Returns 0 on parse failure.
    private static func parseHumanSize(_ raw: String) -> UInt64 {
        let trimmed = raw.split(separator: " ").first.map(String.init) ?? raw
        let scanner = Scanner(string: trimmed)
        scanner.locale = Locale(identifier: "en_US_POSIX")
        guard let value = scanner.scanDouble() else { return 0 }
        let suffix = String(trimmed[scanner.currentIndex...]).uppercased()
        let multiplier: Double
        switch suffix {
        case "B":                       multiplier = 1
        case "K", "KB":                 multiplier = 1_000
        case "M", "MB":                 multiplier = 1_000_000
        case "G", "GB":                 multiplier = 1_000_000_000
        case "T", "TB":                 multiplier = 1_000_000_000_000
        case "P", "PB":                 multiplier = 1_000_000_000_000_000
        case "KI", "KIB":               multiplier = 1_024
        case "MI", "MIB":               multiplier = 1_024 * 1_024
        case "GI", "GIB":               multiplier = 1_024 * 1_024 * 1_024
        case "TI", "TIB":               multiplier = 1_024 * 1_024 * 1_024 * 1_024
        case "PI", "PIB":               multiplier = 1_024 * 1_024 * 1_024 * 1_024 * 1_024
        default:                        multiplier = 0
        }
        return UInt64(max(0, value * multiplier))
    }
}
