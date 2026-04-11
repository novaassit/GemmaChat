import Foundation

/// Downloads GGUF model from HuggingFace with progress tracking.
@MainActor
final class ModelDownloadService: NSObject, ObservableObject {

    nonisolated static let modelURL = URL(string: "https://huggingface.co/bartowski/google_gemma-4-E2B-it-GGUF/resolve/main/google_gemma-4-E2B-it-Q4_K_M.gguf")!
    nonisolated static let modelFilename = "google_gemma-4-E2B-it-Q4_K_M.gguf"

    @Published var isDownloading = false
    @Published var progress: Double = 0  // 0.0 ~ 1.0
    @Published var downloadedMB: Double = 0
    @Published var totalMB: Double = 0
    @Published var error: String?

    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession?
    private var continuation: CheckedContinuation<URL?, Never>?

    /// Returns the Documents directory URL
    nonisolated static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    /// Check if model already exists in Documents
    nonisolated static var modelExists: Bool {
        let docs = documentsDirectory
        let files = (try? FileManager.default.contentsOfDirectory(atPath: docs.path)) ?? []
        return files.contains(where: { $0.hasSuffix(".gguf") })
    }

    /// Start downloading the model
    func download() async -> URL? {
        guard !isDownloading else { return nil }

        isDownloading = true
        progress = 0
        downloadedMB = 0
        totalMB = 0
        error = nil

        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        return await withCheckedContinuation { cont in
            self.continuation = cont
            let task = session!.downloadTask(with: Self.modelURL)
            self.downloadTask = task
            task.resume()
        }
    }

    /// Cancel an in-progress download
    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        progress = 0
        error = "다운로드가 취소되었습니다"
        continuation?.resume(returning: nil)
        continuation = nil
    }
}

// MARK: - URLSessionDownloadDelegate

extension ModelDownloadService: URLSessionDownloadDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let dest = Self.documentsDirectory.appendingPathComponent(Self.modelFilename)

        do {
            // Remove existing file if any
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)

            Task { @MainActor in
                self.isDownloading = false
                self.progress = 1.0
                self.continuation?.resume(returning: dest)
                self.continuation = nil
            }
        } catch {
            Task { @MainActor in
                self.isDownloading = false
                self.error = "파일 저장 실패: \(error.localizedDescription)"
                self.continuation?.resume(returning: nil)
                self.continuation = nil
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let prog = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        let dlMB = Double(totalBytesWritten) / 1_048_576
        let totMB = Double(totalBytesExpectedToWrite) / 1_048_576

        Task { @MainActor in
            self.progress = prog
            self.downloadedMB = dlMB
            self.totalMB = totMB
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error = error else { return }

        // Don't report cancellation as error
        if (error as NSError).code == NSURLErrorCancelled { return }

        Task { @MainActor in
            self.isDownloading = false
            self.error = "다운로드 실패: \(error.localizedDescription)"
            self.continuation?.resume(returning: nil)
            self.continuation = nil
        }
    }
}
