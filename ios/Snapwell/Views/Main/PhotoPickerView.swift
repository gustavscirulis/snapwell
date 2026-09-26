import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct PickerLoadResult {
    let items: [PickedMedia]
    let failureCount: Int
    let selectedCount: Int
}

private enum PickerStaging {
    private static let supportedExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "webm"]

    static func copyVideo(from source: URL, suggestedExtension: String? = nil) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapwellPicker", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sourceExtension = source.pathExtension.lowercased()
            let suggested = suggestedExtension?.lowercased() ?? ""
            let ext = supportedExtensions.contains(sourceExtension) ? sourceExtension : suggested
            guard supportedExtensions.contains(ext) else { return nil }
            let destination = directory.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

struct PhotosPickerWrapper: UIViewControllerRepresentable {
    let onItemsPicked: (PickerLoadResult) -> Void
    let onPreparing: (Int, Int) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0
        config.selection = .ordered
        config.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotosPickerWrapper
        init(_ parent: PhotosPickerWrapper) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            Task { @MainActor in
                parent.onPreparing(0, results.count)
                var items: [PickedMedia] = []
                var failures = 0
                for (index, result) in results.enumerated() {
                    let provider = result.itemProvider
                    if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                        if let video = await loadVideo(from: provider) {
                            items.append(.video(video))
                        } else {
                            failures += 1
                        }
                    } else if provider.canLoadObject(ofClass: UIImage.self) {
                        if let image = await loadImage(from: provider) {
                            items.append(.image(image))
                        } else {
                            failures += 1
                        }
                    } else {
                        failures += 1
                    }
                    parent.onPreparing(index + 1, results.count)
                }
                parent.onItemsPicked(PickerLoadResult(
                    items: items, failureCount: failures, selectedCount: results.count
                ))
            }
        }

        private func loadImage(from provider: NSItemProvider) async -> UIImage? {
            await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            }
        }

        private func loadVideo(from provider: NSItemProvider) async -> URL? {
            let nameExtension = URL(fileURLWithPath: provider.suggestedName ?? "").pathExtension
            let registeredExtension = provider.registeredTypeIdentifiers
                .compactMap { UTType($0) }
                .first { $0.conforms(to: .movie) }?
                .preferredFilenameExtension
            let preferredExtension = !nameExtension.isEmpty ? nameExtension : (registeredExtension ?? "mov")
            return await withCheckedContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { source, _ in
                    continuation.resume(returning: source.flatMap {
                        PickerStaging.copyVideo(from: $0, suggestedExtension: preferredExtension)
                    })
                }
            }
        }
    }
}

struct DocumentPickerWrapper: UIViewControllerRepresentable {
    let onItemsPicked: (PickerLoadResult) -> Void
    let onPreparing: (Int, Int) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .movie])
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerWrapper
        init(_ parent: DocumentPickerWrapper) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            Task { @MainActor in
                parent.onPreparing(0, urls.count)
                var items: [PickedMedia] = []
                var failures = 0
                for (index, url) in urls.enumerated() {
                    let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
                        ?? UTType(filenameExtension: url.pathExtension)
                    if type?.conforms(to: .movie) == true {
                        let video = await Task.detached(priority: .userInitiated) {
                            let accessed = url.startAccessingSecurityScopedResource()
                            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                            return PickerStaging.copyVideo(from: url)
                        }.value
                        if let video {
                            items.append(.video(video))
                        } else {
                            failures += 1
                        }
                    } else if let data = await Task.detached(priority: .userInitiated, operation: {
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        return try? Data(contentsOf: url)
                    }).value, let image = UIImage(data: data) {
                        items.append(.image(image))
                    } else {
                        failures += 1
                    }
                    parent.onPreparing(index + 1, urls.count)
                }
                parent.onItemsPicked(PickerLoadResult(
                    items: items, failureCount: failures, selectedCount: urls.count
                ))
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onItemsPicked(PickerLoadResult(items: [], failureCount: 0, selectedCount: 0))
        }
    }
}
