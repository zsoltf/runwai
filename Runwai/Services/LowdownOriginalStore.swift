import Foundation

// Exceptionally large originals stream to a private file rather than accumulating
// in SwiftUI. The user can read the complete document in the system text reader.
actor LowdownOriginalStore {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("runwai-originals-\(UUID().uuidString)")
    private var files: [String: URL] = [:]
    private var offsets: [String: Int] = [:]

    deinit { try? FileManager.default.removeItem(at: directory) }

    func append(key: String, offset: Int, text: String, total: Int, done: Bool) throws -> URL? {
        guard offset == offsets[key, default: 0], total >= 0 else { throw LowdownBridgeError.invalidOutput }
        let url: URL
        if let existing = files[key] { url = existing }
        else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            url = directory.appendingPathComponent("\(UUID().uuidString).txt")
            FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            files[key] = url
        }
        let data = Data(text.utf8)
        guard data.count <= total - offset else { throw LowdownBridgeError.invalidOutput }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        offsets[key] = offset + data.count
        if done {
            guard offsets[key] == total else { throw LowdownBridgeError.invalidOutput }
            return url
        }
        return nil
    }

    func clear() {
        try? FileManager.default.removeItem(at: directory)
        files = [:]
        offsets = [:]
    }

    func discard(key: String) {
        if let url = files.removeValue(forKey: key) { try? FileManager.default.removeItem(at: url) }
        offsets[key] = nil
    }
}
