import SwiftUI

struct GridColumnChooser: View {
    let preferences: GridColumnPreferences

    private var columnLabel: String {
        preferences.preferredColumnCount == 1 ? "1 column" : "\(preferences.preferredColumnCount) columns"
    }

    private var columnCount: Binding<Double> {
        Binding(
            get: { Double(preferences.preferredColumnCount) },
            set: { preferences.preferredColumnCount = Int($0.rounded()) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Grid columns")
                Spacer(minLength: 12)
                Text(columnLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .accessibilityHidden(true)

            Slider(
                value: columnCount,
                in: Double(preferences.device.minimumColumns)...Double(preferences.device.maximumColumns),
                step: 1
            ) {
                Text("Grid columns")
            } minimumValueLabel: {
                Text("\(preferences.device.minimumColumns)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("\(preferences.device.maximumColumns)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .labelsHidden()
            .frame(minHeight: 44)
            .accessibilityValue(columnLabel)
            .accessibilityIdentifier("grid-columns-slider")
        }
    }
}
