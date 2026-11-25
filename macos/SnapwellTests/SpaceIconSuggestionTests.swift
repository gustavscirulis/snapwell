import Foundation
import Testing
@testable import Snapwell

@Suite("Space icon suggestions")
struct SpaceIconSuggestionTests {
    @Test("Catalog search and local fallback match collection intent")
    func catalogSearchAndFallback() {
        #expect(SpaceSymbolCatalog.search("vacation").contains { $0.name == "airplane" })
        #expect(SpaceSymbolCatalog.search("interface screens").contains { $0.name == "square.on.square" })
        #expect(SpaceSymbolCatalog.fallbackSymbol(for: "Travel photos") == "airplane")
        #expect(SpaceSymbolCatalog.fallbackSymbol(for: "Unmatched collection") == "folder")
    }

    @Test("Structured responses accept only requested ids and catalog symbols")
    func structuredResponseValidation() throws {
        let candidates = [
            SpaceIconCandidate(id: "travel", title: "Travel"),
            SpaceIconCandidate(id: "ideas", title: "Ideas")
        ]
        let response = """
        {"suggestions":[
          {"id":"travel","symbolName":"airplane"},
          {"id":"ideas","symbolName":"not.a.symbol"},
          {"id":"unexpected","symbolName":"star"}
        ]}
        """
        let parsed = try SpaceIconSuggestionService.parse(response, candidates: candidates)
        #expect(parsed == ["travel": "airplane"])
    }

    @Test("Invalid structured responses fail instead of inventing a symbol")
    func invalidResponse() {
        let candidates = [SpaceIconCandidate(id: "ideas", title: "Ideas")]
        #expect(throws: SpaceIconSuggestionService.SuggestionError.invalidResponse) {
            try SpaceIconSuggestionService.parse(
                #"{"suggestions":[{"id":"ideas","symbolName":"not.a.symbol"}]}"#,
                candidates: candidates
            )
        }
    }

    @Test("Installed symbol validation accepts valid names and rejects unknown names")
    @MainActor func installedSymbolValidation() {
        #expect(SpaceIconSuggestionCoordinator.isAvailable("star"))
        #expect(!SpaceIconSuggestionCoordinator.isAvailable("snapwell.not-a-real-symbol"))
    }

    @Test("Backfill candidates are sent to the provider as one batch")
    @MainActor func candidatesAreBatched() async throws {
        let recorder = SuggestionBatchRecorder()
        let coordinator = SpaceIconSuggestionCoordinator(
            service: RecordingSuggestionService(recorder: recorder)
        )
        let candidates = [
            SpaceIconCandidate(id: "travel", title: "Travel"),
            SpaceIconCandidate(id: "ideas", title: "Ideas")
        ]
        var appliedIDs: Set<String> = []

        coordinator.suggest(candidates) { candidate, _ in
            appliedIDs.insert(candidate.id)
        }
        try await Task.sleep(for: .milliseconds(50))
        let batches = await recorder.recordedBatches()

        #expect(batches == [candidates])
        #expect(appliedIDs == Set(candidates.map(\.id)))
    }

    @Test("Cancelling a space ignores an in-flight suggestion")
    @MainActor func cancellationIgnoresStaleResult() async throws {
        let coordinator = SpaceIconSuggestionCoordinator(service: DelayedSuggestionService())
        let candidate = SpaceIconCandidate(id: "space", title: "Travel")
        var applied: String?
        coordinator.suggest([candidate]) { _, symbol in applied = symbol }
        coordinator.cancel(spaceID: candidate.id)
        try await Task.sleep(for: .milliseconds(150))
        #expect(applied == nil)
        #expect(!coordinator.isSuggesting(spaceID: candidate.id))
    }
}

private struct DelayedSuggestionService: SpaceIconSuggesting {
    func suggestSymbols(for candidates: [SpaceIconCandidate]) async throws -> [String: String] {
        try await Task.sleep(for: .milliseconds(75))
        return Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, "airplane") })
    }
}

private actor SuggestionBatchRecorder {
    private var batches: [[SpaceIconCandidate]] = []

    func record(_ candidates: [SpaceIconCandidate]) {
        batches.append(candidates)
    }

    func recordedBatches() -> [[SpaceIconCandidate]] {
        batches
    }
}

private struct RecordingSuggestionService: SpaceIconSuggesting {
    let recorder: SuggestionBatchRecorder

    func suggestSymbols(for candidates: [SpaceIconCandidate]) async throws -> [String: String] {
        await recorder.record(candidates)
        return Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, "folder") })
    }
}
