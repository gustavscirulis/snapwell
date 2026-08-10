import SwiftUI

// MARK: - Detail Metadata Section

struct DetailMetadataSection: View {
    let item: MediaItem
    let stage: Int
    let onRetryAnalysis: () -> Void
    var onSearchPattern: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if item.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Analyzing...")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .stageReveal(stage: stage, threshold: 1)
            } else if item.analysisError != nil {
                AnalysisFailureView(onRetry: onRetryAnalysis)
                    .stageReveal(stage: stage, threshold: 1)
            } else if let result = item.analysisResult {
                if !result.patterns.isEmpty {
                    patternPillsGrid(result.patterns)
                        .padding(.bottom, 16)
                }

                if hasDescription(result) {
                    Text(result.imageContext)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(stage >= 3 ? 1 : 0)
                        .animation(SnapSpring.resolvedMetadata, value: stage)
                }
            }

            HStack(spacing: 0) {
                Text("\(item.width) \u{00D7} \(item.height)")
                Text("  \u{00B7}  ")
                    .foregroundStyle(.white.opacity(0.15))
                Text(item.createdAt, style: .date)
                if let duration = item.duration {
                    Text("  \u{00B7}  ")
                        .foregroundStyle(.white.opacity(0.15))
                    Text(formatDuration(duration))
                }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.white.opacity(0.25))
            .stageReveal(stage: stage, threshold: 4)
            .padding(.top, 16)

            if let urlString = item.sourceURL, let url = URL(string: urlString) {
                SourceLinkButton(url: url)
                    .stageReveal(stage: stage, threshold: 4)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 24)
    }

    private func hasDescription(_ result: AnalysisResult) -> Bool {
        !result.imageContext.isEmpty && result.imageContext != result.imageSummary
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    // MARK: - Pattern pills (glass on iOS 26+, material fallback)

    @ViewBuilder
    private func patternPillsGrid(_ patterns: [PatternTag]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(patterns.enumerated()), id: \.element.name) { index, pattern in
                patternPill(pattern: pattern, index: index)
            }
        }
    }

    @ViewBuilder
    private func patternPill(pattern: PatternTag, index: Int) -> some View {
        let base = Text(pattern.name)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

        if #available(iOS 26.0, *) {
            base
                .environment(\.colorScheme, .dark)
                .glassEffect(.regular.interactive(), in: .capsule)
                .contentShape(Rectangle())
                .accessibilityLabel("Pattern: \(pattern.name)")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Double tap to search for this pattern")
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSearchPattern?(pattern.name)
                }
                .opacity(stage >= 2 ? 1 : 0)
                .offset(y: stage >= 2 ? 0 : MetadataReveal.slideDistance)
                .animation(
                    UIAccessibility.isReduceMotionEnabled
                        ? SnapSpring.resolvedMetadata
                        : SnapSpring.resolvedMetadata.delay(Double(index) * MetadataReveal.tagStagger),
                    value: stage
                )
        } else {
            base
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
                .contentShape(Rectangle())
                .accessibilityLabel("Pattern: \(pattern.name)")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Double tap to search for this pattern")
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSearchPattern?(pattern.name)
                }
                .opacity(stage >= 2 ? 1 : 0)
                .offset(y: stage >= 2 ? 0 : MetadataReveal.slideDistance)
                .animation(
                    UIAccessibility.isReduceMotionEnabled
                        ? SnapSpring.resolvedMetadata
                        : SnapSpring.resolvedMetadata.delay(Double(index) * MetadataReveal.tagStagger),
                    value: stage
                )
        }
    }
}

// MARK: - Analysis Failure

private struct AnalysisFailureView: View {
    let onRetry: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                failureLabel
                Spacer(minLength: 8)
                retryButton
            }

            VStack(alignment: .leading, spacing: 8) {
                failureLabel
                retryButton
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    private var failureLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Analysis failed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Analysis couldn’t be completed.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var retryButton: some View {
        Button {
            onRetry()
        } label: {
            Label("Try Again", systemImage: "arrow.clockwise")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(.red)
        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel("Retry analysis")
        .accessibilityHint("Analyzes this item again")
    }
}

// MARK: - Source Link Button

struct SourceLinkButton: View {
    let url: URL
    @Environment(\.openURL) private var openURL

    private var label: String {
        if let host = url.host?.lowercased(),
           host.contains("x.com") || host.contains("twitter.com") {
            return "View on X"
        }
        return "View source"
    }

    private var iconName: String {
        if let host = url.host?.lowercased(),
           host.contains("x.com") || host.contains("twitter.com") {
            return "arrow.up.right.square"
        }
        return "link"
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .font(.caption2)
            Text(label)
                .font(.footnote)
        }
        .foregroundStyle(.white.opacity(0.35))
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            openURL(url)
        }
        .accessibilityLabel("View original post on X")
        .accessibilityAddTraits(.isLink)
    }
}
