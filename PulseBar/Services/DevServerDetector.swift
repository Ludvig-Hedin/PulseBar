import Foundation

struct DevServerInfo {
    let isDevServer: Bool
    let kind: String?
}

struct DevServerDetector {
    private let hints: [String: String] = [
        "node": "Node",
        "npm": "npm",
        "pnpm": "pnpm",
        "yarn": "yarn",
        "bun": "Bun",
        "vite": "Vite",
        "next": "Next.js",
        "nuxt": "Nuxt",
        "astro": "Astro",
        "python": "Python",
        "uvicorn": "Uvicorn",
        "gunicorn": "Gunicorn",
        "flask": "Flask",
        "django": "Django",
        "docker": "Docker",
        "postgres": "Postgres",
        "redis": "Redis",
        "supabase": "Supabase",
        "ngrok": "ngrok"
    ]

    func detect(appName: String, executablePath: String?, ports: [Int]) -> DevServerInfo {
        let source = "\(appName.lowercased()) \((executablePath ?? "").lowercased())"

        for (hint, label) in hints {
            if source.contains(hint) {
                return .init(isDevServer: true, kind: label)
            }
        }

        let commonDevPorts: Set<Int> = [3000, 3001, 5173, 8000, 8080, 8787, 5432, 6379, 9229]
        if ports.contains(where: { commonDevPorts.contains($0) }) {
            return .init(isDevServer: true, kind: "Server")
        }

        return .init(isDevServer: false, kind: nil)
    }
}
