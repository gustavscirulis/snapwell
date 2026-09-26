import SwiftUI
import UIKit

struct DetailMetadataSection: View {
    let item: MediaItem
    let compact: Bool
    let stage: Int
    let onRetryAnalysis: () -> Void
    var onSearchPattern: ((String) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !hasNarrative {
                record
            } else if compact {
                VStack(alignment: .leading, spacing: 28) {
                    narrative
                    record
                }
            } else {
                HStack(alignment: .top, spacing: 48) {
                    narrative
                        .frame(maxWidth: .infinity, alignment: .leading)
                    record
                        .frame(width: 250)
                }
            }
        }
    }

    private var narrative: some View {
        VStack(alignment: .leading, spacing: 0) {
            if item.isAnalyzing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing…")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .stageReveal(stage: stage, threshold: 1, reduceMotion: reduceMotion)
            } else if item.analysisError != nil {
                AnalysisFailureView(onRetry: onRetryAnalysis)
                    .stageReveal(stage: stage, threshold: 1, reduceMotion: reduceMotion)
            } else if let description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .stageReveal(stage: stage, threshold: 1, reduceMotion: reduceMotion)
            }

            if let patterns = item.analysisResult?.patterns, !patterns.isEmpty {
                Group {
                    if #available(iOS 26, *) {
                        GlassEffectContainer(spacing: 8) {
                            patternFlow(patterns)
                        }
                    } else {
                        patternFlow(patterns)
                    }
                }
                .padding(.top, hasNarrativeLead ? 24 : 0)
            }
        }
    }

    private func patternFlow(_ patterns: [PatternTag]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(patterns.enumerated()), id: \.element.name) { index, pattern in
                patternButton(pattern)
                    .opacity(stage >= 2 ? 1 : 0)
                    .offset(y: reduceMotion || stage >= 2 ? 0 : MetadataReveal.slideDistance)
                    .animation(
                        reduceMotion
                            ? .easeOut(duration: 0.15)
                            : SnapSpring.resolvedMetadata.delay(Double(index) * MetadataReveal.tagStagger),
                        value: stage
                    )
            }
        }
    }

    @ViewBuilder
    private func patternButton(_ pattern: PatternTag) -> some View {
        let button = Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSearchPattern?(pattern.name)
        } label: {
            Text(pattern.name)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pattern: \(pattern.name)")
        .accessibilityHint("Searches for items with this pattern")

        if #available(iOS 26, *) {
            button.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            button.background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var record: some View {
        VStack(spacing: 0) {
            recordRow("Added", item.createdAt.formatted(date: .abbreviated, time: .omitted))
            recordRow("Dimensions", "\(item.width) × \(item.height)", monospacedValue: true)

            let fileExtension = URL(fileURLWithPath: item.filename).pathExtension
            if !fileExtension.isEmpty {
                recordRow("Format", fileExtension.uppercased(), monospacedValue: true)
            }
            if let duration = item.duration {
                recordRow("Duration", formatDuration(duration))
            }
            if let urlString = item.sourceURL, let url = URL(string: urlString) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Original")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    SourceLinkButton(url: url)
                }
                .font(.footnote)
                .padding(.vertical, 13)
            }
        }
        .stageReveal(stage: stage, threshold: 3, reduceMotion: reduceMotion)
    }

    private var description: String? {
        guard let result = item.analysisResult else { return nil }
        let context = result.imageContext.trimmingCharacters(in: .whitespacesAndNewlines)
        return context.isEmpty || context == result.imageSummary ? nil : context
    }

    private var hasNarrativeLead: Bool {
        item.isAnalyzing || item.analysisError != nil || description != nil
    }

    private var hasNarrative: Bool {
        hasNarrativeLead || !(item.analysisResult?.patterns.isEmpty ?? true)
    }

    private func recordRow(_ label: String, _ value: String, monospacedValue: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(monospacedValue ? .footnote.monospaced() : .footnote)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

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
        .accessibilityElement(children: .contain)
    }

    private var failureLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Analysis failed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var retryButton: some View {
        Button {
            onRetry()
        } label: {
            Label("Try Again", systemImage: "arrow.clockwise")
                .font(.footnote.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(.red)
        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
        .accessibilityLabel("Retry analysis")
        .accessibilityHint("Analyzes this item again")
    }
}

struct SourceLinkButton: View {
    let url: URL
    @Environment(\.openURL) private var openURL

    private var label: String {
        guard let host = url.host?.lowercased() else { return "View source" }
        if host == "x.com" || host.hasSuffix(".x.com") ||
            host == "twitter.com" || host.hasSuffix(".twitter.com") {
            return "View on X"
        }
        return "View source"
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            openURL(url)
        } label: {
            Label(label, systemImage: "arrow.up.right")
                .font(.footnote.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityAddTraits(.isLink)
        .accessibilityHint("Opens the original source in your browser")
    }
}
