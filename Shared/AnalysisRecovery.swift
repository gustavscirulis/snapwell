import Foundation
import SwiftData

/// Clears work left behind by an interrupted launch while preserving coordinator-owned work.
enum AnalysisRecovery {
    static func clearStaleFlags(in context: ModelContext, ownedIDs: Set<String> = []) throws -> Int {
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.isAnalyzing == true })
        let stale = try context.fetch(descriptor).filter { !ownedIDs.contains($0.id) }
        for item in stale { item.isAnalyzing = false }
        return stale.count
    }
}
