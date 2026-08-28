import SwiftUI
import SwiftData

struct DeveloperSettingsTab: View {
    @AppStorage("debugSimulateEmptyState") private var simulateEmptyState = false
    @Query private var allItems: [MediaItem]
    @State private var showConfirmReset = false
    @State private var trashEmptied = false
    @State private var trashCount = 0
    @State private var isRegenerating = false
    @State private var regeneratedCount = 0
    @State private var regenerationTotal = 0

    var body: some View {
        Form {
            Section("Simulation") {
                Toggle("Simulate Empty State", isOn: $simulateEmptyState)
                    .accessibilityLabel("Simulate empty state")

                Text("Shows the empty state view without deleting any data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Show AI Setup Toast") {
                    UserDefaults.standard.set(0, forKey: "apiKeyToastCount")
                    NotificationCenter.default.post(name: .showAPIKeyToast, object: nil)
                }

                Text("Resets the counter and triggers the AI setup nudge toast.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Trash") {
                LabeledContent("Items in trash") {
                    Text("\(trashCount)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Empty Trash Now") {
                        MediaStorageService.shared.emptyTrash()
                        trashCount = 0
                        trashEmptied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { trashEmptied = false }
                    }
                    .disabled(trashCount == 0)

                    if trashEmptied {
                        Text("Emptied")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Text("Trash is automatically emptied after 30 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Thumbnails") {
                HStack {
                    Button("Regenerate Thumbnails") {
                        Task {
                            await regenerateAllThumbnails()
                        }
                    }
                    .disabled(isRegenerating)

                    if !isRegenerating && regeneratedCount > 0 {
                        Text("Done — \(regeneratedCount) regenerated")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if isRegenerating {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(
                            value: Double(regeneratedCount),
                            total: Double(max(regenerationTotal, 1))
                        )
                        Text("Regenerating \(regeneratedCount) of \(regenerationTotal)…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Regenerates thumbnail images for all media. Useful if thumbnails appear corrupted or outdated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Danger Zone") {
                Button("Reset All Data", role: .destructive) {
                    showConfirmReset = true
                }
                .alert("Reset All Data?", isPresented: $showConfirmReset) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        resetAllData()
                    }
                } message: {
                    Text("This will delete all media, analysis results, and spaces. This cannot be undone. The app will restart.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { trashCount = countTrashItems() }
    }

    private func countTrashItems() -> Int {
        let fm = FileManager.default
        let dir = MediaStorageService.shared.trashMediaDir
        return (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?.count ?? 0
    }

    private func regenerateAllThumbnails() async {
        let items = allItems
        regenerationTotal = items.count
        regeneratedCount = 0
        isRegenerating = true

        let storage = MediaStorageService.shared

        for item in items {
            let sourceURL = storage.mediaURL(filename: item.filename)

            do {
                switch item.mediaType {
                case .image:
                    _ = try await ThumbnailService.generateThumbnail(
                        from: sourceURL, id: item.id, storage: storage
                    )
                case .video:
                    let posterFrame = try await VideoFrameExtractor.extractPosterFrame(from: sourceURL)
                    _ = try ThumbnailService.generateThumbnail(
                        from: posterFrame, id: item.id, storage: storage
                    )
                }
            } catch {}

            regeneratedCount += 1
        }

        ImageCacheService.shared.clearAll()
        NotificationCenter.default.post(name: .thumbnailsRegenerated, object: nil)
        isRegenerating = false
    }

    private func resetAllData() {
        _ = DataCleanupService.deleteCorruptedStore()

        let fm = FileManager.default
        let storage = MediaStorageService.shared
        for dir in [storage.mediaDir, storage.thumbnailDir, storage.trashMediaDir, storage.trashThumbnailDir] {
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for file in files {
                    try? fm.removeItem(at: file)
                }
            }
        }

        ImageCacheService.shared.clearAll()

        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        try? task.run()

        NSApplication.shared.terminate(nil)
    }
}
