import Foundation
import Observation

/// A saved run: its folder and what its `run.json` says.
struct RunSummary: Identifiable, Equatable, Sendable {
    let folder: URL
    var info: RunInfo
    var id: URL { folder }
}

/// The runs on disk, one folder each under `root`.
@MainActor @Observable
final class RunStore {
    /// `WHYFI_RUNS_ROOT` if set, else `~/Library/Application Support/WhyFi/Runs`.
    nonisolated static var defaultRoot: URL {
        if let override = ProcessInfo.processInfo.environment["WHYFI_RUNS_ROOT"], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory.appending(path: "WhyFi/Runs", directoryHint: .isDirectory)
    }

    let root: URL
    private(set) var runs: [RunSummary] = []
    /// The run being recorded right now, so it isn't shown as interrupted.
    var recordingFolder: URL?

    private let timeZone: TimeZone
    private let trash: (URL) throws -> Void

    init(root: URL = RunStore.defaultRoot, timeZone: TimeZone = .current,
         trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.root = root
        self.timeZone = timeZone
        self.trash = trash
        reload()
    }

    func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        runs = folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appending(path: "run.json")),
                  let info = try? RunInfo.decoder.decode(RunInfo.self, from: data) else { return nil }
            return RunSummary(folder: root.appending(path: folder.lastPathComponent), info: info)
        }
        .sorted { $0.info.startedAt > $1.info.startedAt }
    }

    /// Makes the run's folder, writes its `run.json`, and returns the folder.
    func createRun(info: RunInfo) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let base = folderName(for: info)
        var folder = root.appending(path: base)
        var n = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = root.appending(path: "\(base) \(n)")
            n += 1
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try save(info, in: folder)
        reload()
        return folder
    }

    func save(_ info: RunInfo, in folder: URL) throws {
        let data = try RunInfo.encoder.encode(info)
        try data.write(to: folder.appending(path: "run.json"), options: .atomic)
        if let i = runs.firstIndex(where: { $0.folder == folder }) {
            runs[i].info = info
        }
    }

    /// Changes the name in `run.json`. The folder keeps its original name.
    func rename(_ run: RunSummary, to name: String) throws {
        var info = run.info
        info.name = name
        try save(info, in: run.folder)
    }

    func delete(_ run: RunSummary) throws {
        try trash(run.folder)
        runs.removeAll { $0.id == run.id }
    }

    func isInterrupted(_ run: RunSummary) -> Bool {
        run.info.endedAt == nil && run.folder != recordingFolder
    }

    private func folderName(for info: RunInfo) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HHmm"
        var name = info.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "Run" }
        return "\(f.string(from: info.startedAt)) \(String(name.prefix(60)))"
    }
}
