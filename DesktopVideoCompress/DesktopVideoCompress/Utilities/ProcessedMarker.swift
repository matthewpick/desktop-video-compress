import Foundation

/// Tags files this app produced with an extended attribute.
///
/// The output lands in the same folder we're watching, so without a marker the
/// watcher would immediately queue its own output and loop. An xattr survives
/// renames, which the predecessor's `"_compressed" in filename` check did not.
enum ProcessedMarker {
    static let attributeName = "com.desktopvideocompress.processed"

    @discardableResult
    static func mark(_ url: URL) -> Bool {
        let value = ISO8601DateFormatter().string(from: Date())
        return url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return value.withCString { valuePointer in
                setxattr(path, attributeName, valuePointer, strlen(valuePointer), 0, XATTR_NOFOLLOW) == 0
            }
        }
    }

    static func isMarked(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, attributeName, nil, 0, 0, XATTR_NOFOLLOW) >= 0
        }
    }
}
