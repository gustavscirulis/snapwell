import SwiftUI

struct SpaceSidebarView: View {
    let spaces: [Space]
    @Binding var selection: SidebarItem
    @Binding var pendingEditSpaceId: String?
    let onCreateSpace: () -> Void
    let onDeleteSpace: (String) -> Void
    let onRenameSpace: (String, String) -> Void
    let onReorderSpaces: (Int, Int) -> Void
    let onChangeSpaceMembership: (Set<String>, SpaceMembershipAction) -> Void
    let onToggleHideFromAllMedia: (String) -> Void
    let onSetSpaceSymbol: (String, String) -> Void

    @State private var editingSpaceId: String?
    @State private var editName: String = ""
    @State private var spaceToDelete: Space?
    @State private var dropTargetId: String?
    @State private var iconPickerSpace: Space?
    @FocusState private var isEditingFocused: Bool

    var body: some View {
        List(selection: $selection) {
            Label("All", systemImage: "photo.on.rectangle.angled")
                .tag(SidebarItem.all)
                .listItemTint(Color.accentColor)
                .dropDestination(for: String.self) { strings, _ in
                    handleDropStrings(strings, action: .clearAll)
                } isTargeted: { targeted in
                    dropTargetId = targeted ? "ALL" : nil
                }

            Section("Spaces") {
                ForEach(spaces) { space in
                    spaceRow(space)
                        .tag(SidebarItem.space(space.id))
                }
                .onMove { source, destination in
                    guard let fromIndex = source.first else { return }
                    let toIndex = destination > fromIndex ? destination - 1 : destination
                    onReorderSpaces(fromIndex, toIndex)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        .popover(item: $iconPickerSpace, arrowEdge: .trailing) { space in
            SpaceIconPicker(
                space: space,
                onSelect: { symbolName in
                    onSetSpaceSymbol(space.id, symbolName)
                    iconPickerSpace = nil
                }
            )
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onCreateSpace) {
                Label("New Space", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .alert("Delete Space?", isPresented: Binding(
            get: { spaceToDelete != nil },
            set: { if !$0 { spaceToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                spaceToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let space = spaceToDelete {
                    onDeleteSpace(space.id)
                    spaceToDelete = nil
                }
            }
        } message: {
            if let space = spaceToDelete {
                Text("\"\(space.name)\" contains \(space.items.count) item\(space.items.count == 1 ? "" : "s"). They won't be deleted, but will be unassigned from this space.")
            }
        }
        .onChange(of: pendingEditSpaceId) { _, newValue in
            if let spaceId = newValue,
               let space = spaces.first(where: { $0.id == spaceId }) {
                editName = space.name
                editingSpaceId = spaceId
                pendingEditSpaceId = nil
                isEditingFocused = true
            }
        }
    }

    // MARK: - Space Row

    @ViewBuilder
    private func spaceRow(_ space: Space) -> some View {
        if editingSpaceId == space.id {
            HStack(spacing: 8) {
                Image(systemName: space.symbolName ?? SpaceSymbolCatalog.fallbackName)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                TextField("Name", text: $editName)
                    .focused($isEditingFocused)
                    .onSubmit {
                        onRenameSpace(space.id, editName)
                        editingSpaceId = nil
                    }
                    .onExitCommand { editingSpaceId = nil }
                    .onAppear { isEditingFocused = true }
            }
        } else {
            Label {
                Text(space.name)
            } icon: {
                Image(systemName: space.symbolName ?? SpaceSymbolCatalog.fallbackName)
                    .accessibilityHidden(true)
            }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(space.name)
                .accessibilityValue(space.symbolName ?? SpaceSymbolCatalog.fallbackName)
                .accessibilityIdentifier("space-row-\(space.id)")
                .contextMenu {
                    Button {
                        iconPickerSpace = space
                    } label: {
                        Label("Change Icon…", systemImage: "square.grid.2x2")
                    }
                    Button {
                        editName = space.name
                        editingSpaceId = space.id
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button {
                        onToggleHideFromAllMedia(space.id)
                    } label: {
                        Label(
                            space.hideFromAllMedia ? "Show in All Media" : "Hide from All Media",
                            systemImage: space.hideFromAllMedia ? "eye" : "eye.slash"
                        )
                    }
                    Divider()
                    Button(role: .destructive) {
                        if space.items.isEmpty {
                            onDeleteSpace(space.id)
                        } else {
                            spaceToDelete = space
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .onDoubleClick {
                    editName = space.name
                    editingSpaceId = space.id
                }
                .dropDestination(for: String.self) { strings, _ in
                    handleDropStrings(strings, action: .add(space.id))
                } isTargeted: { targeted in
                    dropTargetId = targeted ? space.id : nil
                }
        }
    }

    // MARK: - Drop Helpers

    private func handleDropStrings(_ strings: [String], action: SpaceMembershipAction) -> Bool {
        for text in strings {
            if text.hasPrefix("snapwell:") {
                let idsString = String(text.dropFirst("snapwell:".count))
                let itemIds = Set(idsString.split(separator: ",").map(String.init))
                if !itemIds.isEmpty {
                    onChangeSpaceMembership(itemIds, action)
                    return true
                }
            }
        }
        return false
    }
}
