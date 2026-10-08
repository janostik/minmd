import Foundation

/// Calls `onChange` whenever the file is written — including editors that save atomically by
/// replacing the file, which is why the watcher re-arms itself after a delete or rename.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start(attempt: 0)
    }

    deinit {
        source?.cancel()
    }

    private func start(attempt: Int) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // The file may be mid-replacement; retry for a few seconds, then give up quietly.
            if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.start(attempt: attempt + 1)
                }
            }
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            if source.data.contains(.delete) || source.data.contains(.rename) {
                source.cancel()
                self.source = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.start(attempt: 0)
                    self?.onChange()
                }
            } else {
                self.onChange()
            }
        }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
    }
}
