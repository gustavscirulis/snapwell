import Foundation
import Testing
@testable import Snapwell

private actor RetryAttemptCounter {
    private var count = 0

    func increment() -> Int {
        count += 1
        return count
    }

    func value() -> Int { count }
}

@Suite("Analysis Coordinator", .tags(.state))
struct AnalysisCoordinatorTests {
    @Test("Queue preserves active work and coalesces duplicate requests")
    func queueCoalescing() throws {
        var queue = AnalysisWorkQueue<String>()

        let addedVideo = queue.enqueue(id: "video", value: "first")
        #expect(addedVideo)
        let firstCandidate = queue.next()
        let first = try #require(firstCandidate)
        #expect(first.id == "video")
        #expect(first.value == "first")

        let addedFirstRerun = queue.enqueue(id: "video", value: "rerun")
        let addedLatestRerun = queue.enqueue(id: "video", value: "latest rerun")
        let addedImage = queue.enqueue(id: "image", value: "queued image")
        let addedImageDuplicate = queue.enqueue(id: "image", value: "latest image")
        #expect(!addedFirstRerun)
        #expect(!addedLatestRerun)
        #expect(addedImage)
        #expect(!addedImageDuplicate)
        #expect(queue.ownedIDs == ["video", "image"])

        let keptVideoForRerun = queue.finishActive(enqueueRerun: true)
        #expect(keptVideoForRerun)
        let rerunCandidate = queue.next()
        let rerun = try #require(rerunCandidate)
        #expect(rerun.id == "video")
        #expect(rerun.value == "latest rerun")
        let keptSecondVideoRerun = queue.finishActive(enqueueRerun: true)
        #expect(!keptSecondVideoRerun)

        let imageCandidate = queue.next()
        let image = try #require(imageCandidate)
        #expect(image.id == "image")
        #expect(image.value == "latest image")
        let keptImageForRerun = queue.finishActive(enqueueRerun: true)
        #expect(!keptImageForRerun)
        #expect(queue.isEmpty)
    }

    @Test("Stopping a queue releases pending and active follow-up work")
    func queueRelease() throws {
        var queue = AnalysisWorkQueue<String>()
        queue.enqueue(id: "active", value: "active")
        let activeCandidate = queue.next()
        _ = try #require(activeCandidate)
        queue.enqueue(id: "queued", value: "queued")
        queue.enqueue(id: "active", value: "active rerun")

        let released = queue.removeAllPending()
        #expect(Set(released.map(\.id)) == ["active", "queued"])
        #expect(queue.ownedIDs == ["active"])

        let keptRerun = queue.finishActive(enqueueRerun: false)
        #expect(!keptRerun)
        #expect(queue.ownedIDs.isEmpty)
        #expect(queue.isEmpty)
    }

    @Test("Cancelled URL request receives actionable OpenRouter copy")
    func cancelledRequestCopy() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        let alert = AnalysisCoordinator.alertState(
            for: error,
            mediaType: .video,
            provider: .openrouter
        )

        #expect(alert.title == "Couldn’t analyze video")
        #expect(alert.message == "The connection to OpenRouter was interrupted. Try again.")
        #expect(!alert.message.localizedCaseInsensitiveContains("cancelled"))
    }

    @Test("Offline and iCloud errors receive specific recovery guidance")
    func recoveryCopy() {
        let offline = AnalysisCoordinator.alertState(
            for: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet),
            mediaType: .image,
            provider: .openrouter
        )
        #expect(offline.title == "Couldn’t analyze image")
        #expect(offline.message == "You appear to be offline. Reconnect, then try again.")

        let unavailable = AnalysisCoordinator.alertState(
            for: AnalysisCoordinator.MediaPreparationError.unavailable(.video),
            mediaType: .video,
            provider: .openrouter
        )
        #expect(unavailable.message.contains("iCloud"))
        #expect(!AnalysisCoordinator.isProviderWideFailure(
            AnalysisCoordinator.MediaPreparationError.unavailable(.video)
        ))
        #expect(AnalysisCoordinator.isProviderWideFailure(
            AIAnalysisService.AnalysisError.apiError(
                statusCode: 429,
                message: "rate limited",
                provider: .openrouter
            )
        ))
    }

    @Test("Unexpected URL cancellation is retried")
    func interruptedRequestRetries() async throws {
        let counter = RetryAttemptCounter()

        let result = try await AIAnalysisService.shared.performWithAnalysisRetries {
            let attempt = await counter.increment()
            if attempt == 1 {
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
            }
            return "success"
        }

        #expect(result == "success")
        #expect(await counter.value() == 2)
    }

    @Test("Swift task cancellation is propagated without retrying")
    func taskCancellationPropagates() async throws {
        let counter = RetryAttemptCounter()
        let task = Task {
            try await AIAnalysisService.shared.performWithAnalysisRetries {
                _ = await counter.increment()
                try await Task.sleep(for: .seconds(30))
                return "unreachable"
            }
        }

        while await counter.value() == 0 {
            await Task.yield()
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected task cancellation")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(await counter.value() == 1)
    }
}
