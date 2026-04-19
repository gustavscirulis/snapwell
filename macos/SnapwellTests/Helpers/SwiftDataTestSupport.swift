import SwiftData
@testable import Snapwell

enum TestContainer {
    static func create() throws -> ModelContainer {
        let schema = Schema([MediaItem.self, Space.self, AnalysisResult.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
