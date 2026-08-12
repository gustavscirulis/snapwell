import Foundation

protocol DownloadRequesting: Sendable {
    func requestDownload(for url: URL)
}

/// Thread-safe iCloud download requester. Repeated scans are intentionally cheap:
/// each canonical URL is submitted to Foundation at most once per cooldown window.
final class DownloadRequester: DownloadRequesting, @unchecked Sendable {
    static let shared = DownloadRequester()

    private let lock = NSLock()
    private let cooldown: TimeInterval
    private let now: @Sendable () -> Date
    private let request: @Sendable (URL) -> Void
    private var lastRequests: [URL: Date] = [:]

    init(
        cooldown: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init,
        request: @escaping @Sendable (URL) -> Void = { url in
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    ) {
        self.cooldown = cooldown
        self.now = now
        self.request = request
    }

    func requestDownload(for url: URL) {
        let canonicalURL = url.standardizedFileURL
        let requestDate = now()

        lock.lock()
        if let previous = lastRequests[canonicalURL],
           requestDate.timeIntervalSince(previous) < cooldown {
            lock.unlock()
            return
        }
        lastRequests[canonicalURL] = requestDate
        lock.unlock()

        request(canonicalURL)
    }
}
