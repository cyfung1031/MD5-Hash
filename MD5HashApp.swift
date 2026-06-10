import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

enum HashError: LocalizedError {
    case unreadableFile
    case droppedItemIsNotAFile

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "The selected file could not be read."
        case .droppedItemIsNotAFile:
            "The dropped item was not a valid file."
        }
    }
}

struct FileHasher {
    static func md5OfFile(
        at url: URL,
        chunkSize: Int = 1 << 20,
        progress: @MainActor @escaping (Double) -> Void
    ) async throws -> String {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        let totalBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        var hasher = Insecure.MD5()
        var bytesRead = 0
        var lastReportedPercent = -1

        while true {
            try Task.checkCancellation()

            // autoreleasepool keeps memory flat: FileHandle.read returns
            // autoreleased Data that otherwise accumulates for the whole loop.
            guard let chunk = try autoreleasepool(invoking: { try handle.read(upToCount: chunkSize) }),
                  !chunk.isEmpty
            else {
                break
            }

            hasher.update(data: chunk)
            bytesRead += chunk.count

            if totalBytes > 0 {
                let fraction = min(Double(bytesRead) / Double(totalBytes), 1.0)
                let percent = Int(fraction * 100)
                if percent != lastReportedPercent {
                    lastReportedPercent = percent
                    await progress(fraction)
                }
            }
        }

        await progress(1)

        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct ContentView: View {
    @State private var fileName: String?
    @State private var hash: String?
    @State private var errorMessage: String?
    @State private var progress = 0.0
    @State private var isHashing = false
    @State private var isTargeted = false
    @State private var justCopied = false
    @State private var hashTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            dropZone

            if isHashing {
                VStack(spacing: 6) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)

                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let hash, let fileName {
                resultView(hash: hash, fileName: fileName)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onDisappear {
            hashTask?.cancel()
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)

            Text("Drop a file here")
                .font(.headline)

            Text("or click to browse")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    isTargeted
                    ? Color.accentColor.opacity(0.1)
                    : Color(nsColor: .quaternarySystemFill)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: browse)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .disabled(isHashing)
        .opacity(isHashing ? 0.6 : 1)
    }

    private func resultView(hash: String, fileName: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                Text(hash)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                Button {
                    copy(hash)
                } label: {
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(justCopied ? .green : .secondary)
                }
                .buttonStyle(.borderless)
                .help(justCopied ? "Copied" : "Copy MD5")
            }

            Text("MD5 is legacy and insecure. Use only for checksums.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            Color(nsColor: .quaternarySystemFill),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // .disabled alone does not reliably block AppKit drop sessions.
        guard !isHashing else { return false }

        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        // Keep the drop callback lightweight; the load completes asynchronously
        // and only Sendable values (Data?/Error?) hop to the main actor.
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
            let data = item as? Data
            Task { @MainActor in
                if let error {
                    showError(error.localizedDescription)
                } else {
                    processDroppedURL(data: data)
                }
            }
        }

        return true
    }

    @MainActor
    private func processDroppedURL(data: Data?) {
        guard let data,
              let url = URL(dataRepresentation: data, relativeTo: nil),
              url.isFileURL
        else {
            showError(HashError.droppedItemIsNotAFile.localizedDescription)
            return
        }

        startHashing(url)
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK,
              let url = panel.url
        else {
            return
        }

        startHashing(url)
    }

    @MainActor
    private func startHashing(_ url: URL) {
        hashTask?.cancel()

        fileName = url.lastPathComponent
        hash = nil
        errorMessage = nil
        progress = 0
        isHashing = true
        justCopied = false

        hashTask = Task {
            do {
                let digest = try await FileHasher.md5OfFile(at: url) { fraction in
                    progress = fraction
                }

                guard !Task.isCancelled else { return }

                hash = digest
                isHashing = false
            } catch is CancellationError {
                // A newer file was selected. Ignore this result.
            } catch {
                guard !Task.isCancelled else { return }

                showError(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func showError(_ message: String) {
        hash = nil
        errorMessage = message
        progress = 0
        isHashing = false
        justCopied = false
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)

        justCopied = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            justCopied = false
        }
    }
}

@main
struct MD5HashApp: App {
    var body: some Scene {
        WindowGroup("MD5 Hash") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
