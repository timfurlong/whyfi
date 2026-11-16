import Foundation

/// Keeps saved runs parsed, so the window doesn't re-read a run's CSV on every redraw.
@MainActor
final class RunCache {
    private let load: (RunSummary) -> LoadedRun?
    private var cached: [URL: (info: RunInfo, run: LoadedRun)] = [:]

    init(load: @escaping (RunSummary) -> LoadedRun? = { try? RunLoader.load($0) }) {
        self.load = load
    }

    /// The parsed run, read again only when its `run.json` changed (renamed, or it ended).
    func run(for summary: RunSummary) -> LoadedRun? {
        if let hit = cached[summary.folder], hit.info == summary.info { return hit.run }
        guard let run = load(summary) else { return nil }
        cached[summary.folder] = (summary.info, run)
        return run
    }
}
