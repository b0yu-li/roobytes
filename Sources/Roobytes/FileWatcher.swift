import Foundation

/// Watches a single file for external modifications using GCD file-system events.
/// Fires the callback on the main queue when the file is written or replaced.
@MainActor
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private nonisolated(unsafe) var fileDescriptor: Int32 = -1
    private(set) var url: URL?
    private var lastModDate: Date?
    var onChange: (() -> Void)?

    init() {}

    func watch(_ fileURL: URL) {
        stop()
        url = fileURL
        lastModDate = modificationDate(of: fileURL)
        startSource(for: fileURL)
    }

    func stop() {
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
            fileDescriptor = -1
        }
        url = nil
        lastModDate = nil
    }

    /// Call after saving to update the baseline and re-watch (atomic writes change the inode).
    func noteDidSave() {
        guard let url else { return }
        lastModDate = modificationDate(of: url)
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
            fileDescriptor = -1
        }
        startSource(for: url)
    }

    /// Checks whether the file changed since last snapshot; returns true if reload is needed.
    func checkForExternalChange() -> Bool {
        guard let url else { return false }
        guard let current = modificationDate(of: url) else { return false }
        guard let last = lastModDate else {
            lastModDate = current
            return false
        }
        if current > last {
            lastModDate = current
            return true
        }
        return false
    }

    // MARK: - Private

    private func startSource(for fileURL: URL) {
        let fd = Darwin.open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleEvent()
            }
        }
        src.setCancelHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.fileDescriptor >= 0 {
                    Darwin.close(self.fileDescriptor)
                    self.fileDescriptor = -1
                }
            }
        }
        source = src
        src.resume()
    }

    private func handleEvent() {
        guard let src = source else { return }
        let flags = src.data

        if flags.contains(.delete) || flags.contains(.rename) {
            source?.cancel()
            source = nil
            if fileDescriptor >= 0 {
                Darwin.close(fileDescriptor)
                fileDescriptor = -1
            }
            guard url != nil else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, let url = self.url else { return }
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                self.startSource(for: url)
                if self.checkForExternalChange() {
                    self.onChange?()
                }
            }
            return
        }

        if checkForExternalChange() {
            onChange?()
        }
    }

    private func modificationDate(of fileURL: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
    }
}
