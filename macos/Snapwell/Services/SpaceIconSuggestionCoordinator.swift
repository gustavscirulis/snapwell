import AppKit
import Observation

@Observable
@MainActor
final class SpaceIconSuggestionCoordinator {
    @ObservationIgnored private let service: any SpaceIconSuggesting
    @ObservationIgnored private var generations: [String: Int] = [:]
    private(set) var suggestingIDs: Set<String> = []

    init(service: any SpaceIconSuggesting = SpaceIconSuggestionService.shared) {
        self.service = service
    }

    func suggest(
        _ candidates: [SpaceIconCandidate],
        apply: @escaping @MainActor (_ candidate: SpaceIconCandidate, _ symbolName: String) -> Void
    ) {
        guard !candidates.isEmpty else { return }
        var requestedGenerations: [String: Int] = [:]
        for candidate in candidates {
            let generation = (generations[candidate.id] ?? 0) + 1
            generations[candidate.id] = generation
            requestedGenerations[candidate.id] = generation
            suggestingIDs.insert(candidate.id)
        }

        Task { [weak self, service] in
            let suggestions = (try? await service.suggestSymbols(for: candidates)) ?? [:]
            guard !Task.isCancelled, let self else { return }
            for candidate in candidates {
                guard generations[candidate.id] == requestedGenerations[candidate.id] else { continue }
                let suggested = suggestions[candidate.id]
                    ?? SpaceSymbolCatalog.fallbackSymbol(for: candidate.title)
                let validated = Self.isAvailable(suggested)
                    ? suggested
                    : SpaceSymbolCatalog.fallbackName
                apply(candidate, validated)
                suggestingIDs.remove(candidate.id)
            }
        }
    }

    func cancel(spaceID: String) {
        generations[spaceID] = (generations[spaceID] ?? 0) + 1
        suggestingIDs.remove(spaceID)
    }

    func isSuggesting(spaceID: String) -> Bool {
        suggestingIDs.contains(spaceID)
    }

    static func isAvailable(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}
