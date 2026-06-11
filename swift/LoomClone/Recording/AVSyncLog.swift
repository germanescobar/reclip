import Foundation

/// Diagnostics for A/V sync investigations. Mirrored to a file because the
/// app is normally launched from Finder, where stdout is not visible.
func avSyncLog(_ message: String) {
    let line = "[AVSync] \(Date()) \(message)"
    print(line)

    let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("loomclone-avsync.log")
    guard let data = (line + "\n").data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: logURL) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    } else {
        try? data.write(to: logURL)
    }
}
