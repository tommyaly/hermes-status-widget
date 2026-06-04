import Foundation

enum WidgetSnapshotStore {
    static let directoryName = "HermesStatusWidget"
    static let fileName = "snapshot.json"
    static let widgetBundleIdentifier = "local.hermes.statuswidget.widget"

    static var fallbackSnapshotURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static var widgetContainerSnapshotURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(widgetBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static var snapshotURLs: [URL] {
        unique([fallbackSnapshotURL, widgetContainerSnapshotURL])
    }

    static func write(_ snapshot: HermesSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(snapshot)
            for url in snapshotURLs {
                write(data, to: url)
            }
        } catch {
            // Widget snapshots are best-effort; the menu bar app remains the source of truth.
        }
    }

    private static func write(_ data: Data, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Widget snapshots are best-effort; the menu bar app remains the source of truth.
        }
    }

    static func read() -> HermesSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for url in snapshotURLs {
            do {
                let data = try Data(contentsOf: url)
                return try decoder.decode(HermesSnapshot.self, from: data)
            } catch {
                continue
            }
        }

        return .empty
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            let key = url.standardizedFileURL.path
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }
}
