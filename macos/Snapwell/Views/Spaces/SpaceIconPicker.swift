import SwiftUI

struct SpaceIconPicker: View {
    let space: Space
    let onSelect: (String) -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private let columns = Array(repeating: GridItem(.fixed(42), spacing: 8), count: 7)

    private var availableSymbols: [SpaceSymbol] {
        SpaceSymbolCatalog.search(query).filter { SpaceIconSuggestionCoordinator.isAvailable($0.name) }
    }

    private var sections: [(String, [SpaceSymbol])] {
        Dictionary(grouping: availableSymbols, by: \.category)
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    private var exactName: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canUseExactName: Bool {
        !exactName.isEmpty
            && !SpaceSymbolCatalog.names.contains(exactName)
            && SpaceIconSuggestionCoordinator.isAvailable(exactName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: space.symbolName ?? SpaceSymbolCatalog.fallbackName)
                    .font(.title2)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                Text("Choose an icon")
                    .font(.headline)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current icon: \(space.symbolName ?? SpaceSymbolCatalog.fallbackName)")
            .accessibilityIdentifier("current-space-icon")

            TextField("Search…", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .focused($searchFocused)
                .accessibilityIdentifier("space-icon-search")
                .onSubmit {
                    if canUseExactName { onSelect(exactName) }
                }

            if canUseExactName {
                Button {
                    onSelect(exactName)
                } label: {
                    Label("Use \(exactName)", systemImage: exactName)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("use-exact-space-icon")
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if sections.isEmpty {
                        ContentUnavailableView(
                            "No matching icons",
                            systemImage: "magnifyingglass",
                            description: Text("Enter an exact icon name to use any icon installed on this Mac.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    } else {
                        ForEach(sections, id: \.0) { category, symbols in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(category)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(symbols) { symbol in
                                        symbolButton(symbol)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .frame(width: 390, height: 480)
        .onAppear { searchFocused = true }
    }

    private func symbolButton(_ symbol: SpaceSymbol) -> some View {
        let selected = space.symbolName == symbol.name
        return Button {
            onSelect(symbol.name)
        } label: {
            Image(systemName: symbol.name)
                .font(.system(size: 17))
                .frame(width: 34, height: 34)
                .background(selected ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(.rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(symbol.title)
        .accessibilityLabel(symbol.title)
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityIdentifier("space-icon-\(symbol.name)")
    }
}
