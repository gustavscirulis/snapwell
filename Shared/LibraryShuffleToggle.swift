import SwiftUI

struct LibraryShuffleToggle: View {
    @Bindable var preferences: LibraryShufflePreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Shuffle library", isOn: $preferences.isEnabled)
                .toggleStyle(.switch)
                .accessibilityIdentifier("library-shuffle-toggle")
            Text("Show media in random order. Turn off to show newest first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
