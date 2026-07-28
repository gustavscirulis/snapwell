import Foundation
import Combine

/// Serializes one `waitForDownload` call's resume-once flag with its cancellation handles, which
/// are written by the caller and read by whichever of the sink or the timeout fires first.
private final class DownloadWaitState: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private var cancellable: AnyCancellable?
    private var timeoutTask: Task<Void, Never>?

    /// True for exactly one caller — the one that should resume the continuation.
    func claim() -> Bool {
        lock.lock()
        guard !resumed else {
            lock.unlock()
            return false
        }
        resumed = true
        let pendingCancellable = cancellable
        let pendingTimeout = timeoutTask
        cancellable = nil
        timeoutTask = nil
        lock.unlock()

        pendingCancellable?.cancel()
        pendingTimeout?.cancel()
        return true
    }

    func store(cancellable: AnyCancellable, timeoutTask: Task<Void, Never>) {
        lock.lock()
        guard !resumed else {
            lock.unlock()
            // Already resolved — often synchronously, when the file was ready on subscribe.
            cancellable.cancel()
            timeoutTask.cancel()
            return
        }
        self.cancellable = cancellable
        self.timeoutTask = timeoutTask
        lock.unlock()
    }
}

/// Centralized monitor for iCloud file downloads.
/// Tracks requested downloads and polls their status, publishing updates
/// when files become available.
class iCloudDownloadMonitor {
    static let shared = iCloudDownloadMonitor()

    /// Publishes file URLs that have just finished downloading
    let fileReady = PassthroughSubject<URL, Never>()

    private var pendingDownloads: Set<URL> = []
    private var pollingTask: Task<Void, Never>?
    private let lock = NSLock()
    private let pollInterval: TimeInterval = 3.0

    private init() {}

    /// Request download of an iCloud file and monitor it.
    func requestDownload(for url: URL) {
        lock.lock()
        let isNew = pendingDownloads.insert(url).inserted
        lock.unlock()

        if isNew {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            startPollingIfNeeded()
        }
    }

    /// Check if a file is currently downloaded/local.
    /// Clears cached resource values first to get fresh iCloud status.
    func isDownloaded(_ url: URL) -> Bool {
        var freshURL = url
        freshURL.removeAllCachedResourceValues()
        guard let values = try? freshURL.resourceValues(
            forKeys: [.ubiquitousItemDownloadingStatusKey]
        ) else {
            // Can't read resource values — assume local file
            return true
        }
        guard let status = values.ubiquitousItemDownloadingStatus else {
            // No iCloud status — non-iCloud file
            return true
        }
        return status == .current
    }

    private func startPollingIfNeeded() {
        lock.lock()
        guard pollingTask == nil else {
            lock.unlock()
            return
        }

        let task = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 3.0))
                guard let self = self else { break }
                self.checkPendingDownloads()
            }
        }
        pollingTask = task
        lock.unlock()
    }

    /// Wait for a specific file to finish downloading from iCloud.
    /// Returns when the file is ready or the timeout expires.
    func waitForDownload(of url: URL, timeout: TimeInterval = 120) async {
        if isDownloaded(url) { return }
        requestDownload(for: url)

        // The sink runs on the polling task's thread while the continuation body still runs on the
        // caller's, so the cancellation handles have to live behind the same lock as the resumed
        // flag rather than in captured locals.
        let state = DownloadWaitState()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if Task.isCancelled {
                continuation.resume()
                return
            }

            let cancellable = fileReady
                .filter { $0.absoluteString == url.absoluteString }
                .first()
                .sink { _ in
                    if state.claim() { continuation.resume() }
                }

            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(timeout))
                if state.claim() { continuation.resume() }
            }

            state.store(cancellable: cancellable, timeoutTask: timeoutTask)
        }
    }

    private func checkPendingDownloads() {
        lock.lock()
        let urls = pendingDownloads
        lock.unlock()

        guard !urls.isEmpty else { return }

        var completed: [URL] = []
        for url in urls {
            if isDownloaded(url) {
                completed.append(url)
            }
        }

        if !completed.isEmpty {
            lock.lock()
            for url in completed {
                pendingDownloads.remove(url)
            }
            let shouldStop = pendingDownloads.isEmpty
            lock.unlock()

            for url in completed {
                fileReady.send(url)
            }

            if shouldStop {
                lock.lock()
                pollingTask?.cancel()
                pollingTask = nil
                lock.unlock()
            }
        }
    }
}
