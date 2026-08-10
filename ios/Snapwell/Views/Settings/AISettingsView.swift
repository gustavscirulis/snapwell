import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject private var fileSystem: FileSystemManager
    @EnvironmentObject private var keySyncService: KeySyncService
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput = ""
    @State private var hasKey = false
    @State private var saveError: String?
    @State private var keyWarning: String?
    @State private var discoveryError: String?
    @State private var discoveredModels: [DiscoveredModel] = []
    @State private var isLoadingModels = false
    @State private var showsRemoveConfirmation = false

    private var provider: AIProvider {
        keySyncService.activeProvider.flatMap(AIProvider.init(rawValue:)) ?? .openai
    }

    private var providerBinding: Binding<String> {
        Binding(
            get: { provider.rawValue },
            set: { rawValue in
                guard let provider = AIProvider(rawValue: rawValue) else { return }
                keySyncService.selectProvider(provider, rootURL: fileSystem.rootURL)
            }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { keySyncService.modelSelection(for: provider) },
            set: { model in
                keySyncService.setModel(model, for: provider, rootURL: fileSystem.rootURL)
            }
        )
    }

    private var keyPlaceholder: String {
        switch provider {
        case .openai: "sk-..."
        case .anthropic: "sk-ant-..."
        case .gemini: "AIza..."
        case .openrouter: "sk-or-..."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: providerBinding) {
                        ForEach(AIProvider.allCases, id: \.rawValue) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }
                } header: {
                    Text("Provider")
                } footer: {
                    Text("Snapwell sends media directly to the provider you choose. Your API key is stored securely in Keychain.")
                }

                Section("API Key") {
                    if hasKey {
                        Label("API Key Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("\(provider.displayName) API key saved")

                        Button("Remove API Key", role: .destructive) {
                            showsRemoveConfirmation = true
                        }
                    } else {
                        SecureField(keyPlaceholder, text: $apiKeyInput)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(saveAPIKey)

                        Button("Save API Key") {
                            saveAPIKey()
                        }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if let keyWarning {
                        Label(keyWarning, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    if let saveError {
                        Label(saveError, systemImage: "xmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if hasKey {
                    modelSection
                }
            }
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: provider) {
            hasKey = keySyncService.hasAPIKey(for: provider)
            apiKeyInput = ""
            keyWarning = nil
            saveError = nil
            await loadModels(for: provider)
        }
        .confirmationDialog(
            "Remove \(provider.displayName) API Key?",
            isPresented: $showsRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove API Key", role: .destructive) {
                removeAPIKey()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("AI analysis with this provider will stop until you save another key.")
        }
    }

    @ViewBuilder
    private var modelSection: some View {
        Section {
            if isLoadingModels {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading available models…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if !discoveredModels.isEmpty {
                Picker("Model", selection: modelBinding) {
                    Text(recommendedLabel)
                        .tag(ModelDiscoveryService.autoModelValue)

                    let current = keySyncService.modelSelection(for: provider)
                    if current != ModelDiscoveryService.autoModelValue,
                       !discoveredModels.contains(where: { $0.id == current }) {
                        Text(current).tag(current)
                    }

                    ForEach(discoveredModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
            } else {
                TextField("Model ID", text: modelBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Text("Use “auto” to let Snapwell choose the recommended model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let discoveryError {
                Label(discoveryError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Model")
        } footer: {
            Text("Recommended automatically chooses a current vision-capable model and can recover if that model is retired.")
        }
    }

    private var recommendedLabel: String {
        let preferred = ModelDiscoveryService.shared.preferredModel(from: discoveredModels, for: provider)
            ?? discoveredModels.first
        return "Recommended (\(preferred?.displayName ?? provider.defaultModel))"
    }

    private func saveAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        keyWarning = validateKeyPrefix(key, provider: provider)
        do {
            try keySyncService.saveAPIKey(key, for: provider, rootURL: fileSystem.rootURL)
            ModelDiscoveryService.shared.clearCache(for: provider)
            apiKeyInput = ""
            saveError = nil
            hasKey = true
            Task { await loadModels(for: provider) }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func removeAPIKey() {
        do {
            try keySyncService.removeAPIKey(for: provider, rootURL: fileSystem.rootURL)
            ModelDiscoveryService.shared.clearCache(for: provider)
            apiKeyInput = ""
            saveError = nil
            keyWarning = nil
            discoveryError = nil
            discoveredModels = []
            hasKey = false
        } catch {
            saveError = error.localizedDescription
        }
    }

    @MainActor
    private func loadModels(for requestedProvider: AIProvider) async {
        guard keySyncService.hasAPIKey(for: requestedProvider) else {
            discoveredModels = []
            discoveryError = nil
            isLoadingModels = false
            return
        }

        isLoadingModels = true
        discoveryError = nil
        defer {
            if provider == requestedProvider {
                isLoadingModels = false
            }
        }

        do {
            let models = try await ModelDiscoveryService.shared.fetchModels(for: requestedProvider)
            guard provider == requestedProvider else { return }
            discoveredModels = models
            if models.isEmpty {
                discoveryError = "No compatible vision models were returned. Enter a model ID manually."
            }
        } catch {
            guard provider == requestedProvider else { return }
            discoveredModels = []
            discoveryError = "Couldn’t load models. You can enter a model ID manually."
        }
    }

    private func validateKeyPrefix(_ key: String, provider: AIProvider) -> String? {
        switch provider {
        case .openai where !key.hasPrefix("sk-"):
            "OpenAI keys typically start with “sk-”."
        case .anthropic where !key.hasPrefix("sk-ant-"):
            "Anthropic keys typically start with “sk-ant-”."
        case .gemini where !key.hasPrefix("AIza"):
            "Gemini keys typically start with “AIza”."
        case .openrouter where !key.hasPrefix("sk-or-"):
            "OpenRouter keys typically start with “sk-or-”."
        default:
            nil
        }
    }
}

#Preview {
    AISettingsView()
        .environmentObject(FileSystemManager())
        .environmentObject(KeySyncService.shared)
}
