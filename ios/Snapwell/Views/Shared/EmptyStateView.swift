import SwiftUI

struct EmptyStateView: View {

    // Varied heights for skeleton placeholders (matches Mac app pattern)
    private let skeletonHeights: [CGFloat] = [
        180, 260, 200, 320, 150, 280, 220, 300,
        170, 250, 190, 340, 160, 270, 210, 290,
    ]

    @Environment(AppState.self) private var appState
    private let spacing: CGFloat = 8    // Match MasonryGrid
    private let padding: CGFloat = 12   // Match grid horizontal padding

    var body: some View {
        GeometryReader { geometry in
            let columns = appState.gridColumns.columns(
                availableWidth: geometry.size.width - padding * 2, spacing: spacing
            )
            let totalSpacing = spacing * CGFloat(columns - 1) + padding * 2
            let columnWidth = (geometry.size.width - totalSpacing) / CGFloat(columns)

            // Ghost grid background — aligned to top
            HStack(alignment: .top, spacing: spacing) {
                ForEach(0..<columns, id: \.self) { col in
                    VStack(spacing: spacing) {
                        ForEach(0..<4, id: \.self) { row in
                            let index = col * 4 + row
                            let h = skeletonHeights[index % skeletonHeights.count]
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.snapMuted.opacity(0.5))
                                .frame(width: columnWidth, height: h)
                        }
                    }
                }
            }
            .padding(.horizontal, padding)
            .opacity(0.5)

            EmptyStateContent(
                icon: "photo.on.rectangle.angled",
                title: "Add images or videos",
                subtitle: "Tap + to import from Photos,\nor share from any app"
            )
            .frame(maxWidth: geometry.size.width - 48)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}

private struct EmptyStateContent: View {
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.snapMutedForeground)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.snapForeground)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.snapMutedForeground)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct SearchEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.snapMutedForeground)

            Text("No results found")
                .font(.headline)
                .foregroundStyle(Color.snapForeground)
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlaceholderView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        GeometryReader { geometry in
            EmptyStateContent(icon: icon, title: title, subtitle: subtitle)
                .frame(maxWidth: geometry.size.width - 48)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.snapMutedForeground)

            Text("Something went wrong")
                .font(.headline)
                .foregroundStyle(Color.snapForeground)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.snapMutedForeground)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task { await retry() }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.snapForeground)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.snapMuted)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
    }
}
