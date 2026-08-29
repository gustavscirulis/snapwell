import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var fileSystem: FileSystemManager
    @EnvironmentObject var keySyncService: KeySyncService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @State private var keyRefreshTask: Task<Void, Never>?

    var body: some View {
        Group {
            if fileSystem.isAccessGranted {
                MainView()
            } else {
                ZStack {
                    Color.snapDarkBackground
                        .ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: fileSystem.isAccessGranted)
        .onAppear {
            fileSystem.restoreAccess()
        }
        .task {
            for await granted in fileSystem.$isAccessGranted.values where granted {
                refreshKeySettings()
                break
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                keyRefreshTask?.cancel()
                return
            }
            if !fileSystem.isAccessGranted {
                fileSystem.restoreAccess()
            }
            if !fileSystem.isUsingiCloud {
                fileSystem.checkAndMigrateToiCloud(context: modelContext)
            }
            refreshKeySettings()
        }
        .onChange(of: fileSystem.isUsingiCloud) { _, usingiCloud in
            if usingiCloud {
                refreshKeySettings()
            } else {
                keyRefreshTask?.cancel()
            }
        }
        .onDisappear {
            keyRefreshTask?.cancel()
        }
    }

    private func refreshKeySettings() {
        keyRefreshTask?.cancel()

        guard let rootURL = fileSystem.rootURL else {
            keySyncService.checkForSettingsKeys()
            return
        }
        guard fileSystem.isUsingiCloud else {
            keySyncService.checkForKeys(rootURL: rootURL)
            return
        }

        keyRefreshTask = Task {
            await keySyncService.refreshFromiCloud(rootURL: rootURL)
        }
    }
}
