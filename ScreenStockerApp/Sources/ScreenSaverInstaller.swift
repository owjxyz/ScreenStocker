import Foundation

enum ScreenSaverInstallError: LocalizedError {
    case sourceNotFound

    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "Could not find ScreenStocker.saver to install."
        }
    }
}

final class ScreenSaverInstaller {
    private let fileManager: FileManager
    private let saverName = "ScreenStocker.saver"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var installURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Screen Savers", isDirectory: true)
            .appendingPathComponent(saverName, isDirectory: true)
    }

    func reinstall() throws {
        let sourceURL = try sourceScreenSaverURL()
        let installDirectory = installURL.deletingLastPathComponent()

        try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: installURL.path) {
            try fileManager.removeItem(at: installURL)
        }

        try fileManager.copyItem(at: sourceURL, to: installURL)
        clearScreenSaverRenderingCache()
        refreshScreenSaverHosts()
    }

    private func sourceScreenSaverURL() throws -> URL {
        let appURL = Bundle.main.bundleURL
        let productDirectory = appURL.deletingLastPathComponent()
        let resourceDirectory = Bundle.main.resourceURL

        let candidates = [
            resourceDirectory?.appendingPathComponent(saverName, isDirectory: true),
            productDirectory.appendingPathComponent(saverName, isDirectory: true),
            appURL.appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("PlugIns", isDirectory: true)
                .appendingPathComponent(saverName, isDirectory: true)
        ].compactMap { $0 }

        for candidate in candidates where isInstallableScreenSaver(at: candidate) {
            return candidate
        }

        throw ScreenSaverInstallError.sourceNotFound
    }

    private func isInstallableScreenSaver(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return url.standardizedFileURL != installURL.standardizedFileURL
    }

    private func refreshScreenSaverHosts() {
        for processName in [
            "cfprefsd",
            "System Settings",
            "legacyScreenSaver",
            "ScreenSaverEngine",
            "WallpaperAgent",
            "wallpaperAgent"
        ] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            task.arguments = ["-x", processName]
            try? task.run()
            task.waitUntilExit()
        }
    }

    private func clearScreenSaverRenderingCache() {
        let cacheURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches", isDirectory: true)
            .appendingPathComponent("com.apple.wallpaper.caches", isDirectory: true)
            .appendingPathComponent("screenSaver-\(installURL.path)", isDirectory: true)

        if fileManager.fileExists(atPath: cacheURL.path) {
            try? fileManager.removeItem(at: cacheURL)
        }
    }
}
