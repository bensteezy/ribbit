import Foundation

enum GhosttyResources {
    static func terminfoURL(
        bundle: Bundle = .main,
        sourceFilePath: String = #filePath,
        fileManager: FileManager = .default
    ) -> URL? {
        let bundled = bundle.resourceURL?
            .appendingPathComponent("terminfo", isDirectory: true)
        let sourceRoot = URL(fileURLWithPath: sourceFilePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let development = sourceRoot
            .appendingPathComponent("Vendor", isDirectory: true)
            .appendingPathComponent("GhosttyResources", isDirectory: true)
            .appendingPathComponent("terminfo", isDirectory: true)

        return [bundled, development]
            .compactMap { $0 }
            .first {
                fileManager.fileExists(
                    atPath: $0
                        .appendingPathComponent("78", isDirectory: true)
                        .appendingPathComponent("xterm-ghostty", isDirectory: false)
                        .path
                )
            }
    }
}
