import AppKit
import SwiftUI

struct FileInspector: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    let metrics: RibbitLayoutMetrics

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("files", systemImage: "folder")
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.system(size: settings.filesTextSize, weight: .medium))
                Spacer()
            }
            .foregroundStyle(RibbitTheme.ink)
            .frame(height: 30)
            .padding(.top, RibbitTheme.Space.xs)
            .padding(.horizontal, RibbitTheme.Space.sm)
            .padding(.bottom, RibbitTheme.Space.xs)

            Divider().overlay(RibbitTheme.rule)

            files
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.projectURL.lastPathComponent)
                    .font(.system(size: settings.filesTextSize, weight: .semibold))
                    .foregroundStyle(RibbitTheme.ink)
                if metrics.showsProjectPath {
                    Text(model.projectURL.path)
                        .font(.system(size: max(9, settings.filesTextSize - 1)))
                        .foregroundStyle(RibbitTheme.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, RibbitTheme.Space.sm)
            .padding(.vertical, RibbitTheme.Space.sm)

            ScrollView {
                FileTree(directoryURL: model.projectURL, model: model, metrics: metrics, depth: 0)
                    .padding(.horizontal, RibbitTheme.Space.xs)
                    .padding(.bottom, RibbitTheme.Space.md)
            }
        }
    }

}

private struct FileTree: View {
    let directoryURL: URL
    @ObservedObject var model: AppModel
    let metrics: RibbitLayoutMetrics
    let depth: Int
    private var children: [FileNode] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return [] }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return FileNode(url: url, isDirectory: values.isDirectory == true)
        }
        .sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            let firstIsHidden = $0.displayName.hasPrefix(".")
            let secondIsHidden = $1.displayName.hasPrefix(".")
            if firstIsHidden != secondIsHidden { return !firstIsHidden }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(children) { node in
                if node.isDirectory {
                    Button {
                        toggle(node)
                    } label: {
                        FileRowContent(
                            node: node,
                            metrics: metrics,
                            isExpanded: expandedDirectoryIDs.contains(node.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("new terminal here", systemImage: "terminal") {
                            model.newTerminal(at: node.url)
                        }
                        Button {
                            model.ribbitHere(node.url)
                        } label: {
                            Label {
                                Text("ribbit here")
                            } icon: {
                                Image(nsImage: FrogPixelArt.menuIcon)
                                    .resizable()
                                    .interpolation(.none)
                                    .frame(width: 18, height: 16)
                                    .accessibilityHidden(true)
                            }
                        }
                        Divider()
                        Button("show in finder", systemImage: "finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([node.url])
                        }
                    }

                    if expandedDirectoryIDs.contains(node.id), depth < 24 {
                            FileTree(directoryURL: node.url, model: model, metrics: metrics, depth: depth + 1)
                                .padding(.leading, metrics.treeIndent)
                    }
                } else {
                    FileRow(node: node, metrics: metrics) { model.openFile(node.url) }
                        .contextMenu {
                            Button("open", systemImage: "arrow.up.forward.app") {
                                model.openFile(node.url)
                            }
                            Button("show in finder", systemImage: "finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([node.url])
                            }
                        }
                }
            }
        }
    }

    @State private var expandedDirectoryIDs: Set<URL> = []

    private func toggle(_ node: FileNode) {
        if expandedDirectoryIDs.contains(node.id) {
            expandedDirectoryIDs.remove(node.id)
        } else {
            expandedDirectoryIDs.insert(node.id)
        }
    }
}

private struct FileRow: View {
    let node: FileNode
    let metrics: RibbitLayoutMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FileRowContent(node: node, metrics: metrics, isExpanded: nil)
        }
        .buttonStyle(.plain)
    }
}

private struct FileRowContent: View {
    let node: FileNode
    let metrics: RibbitLayoutMetrics
    let isExpanded: Bool?

    var body: some View {
        HStack(spacing: 8) {
            if let isExpanded {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: max(8, metrics.fileFontSize - 2), weight: .semibold))
                    .foregroundStyle(RibbitTheme.muted)
                    .frame(width: 8)
            } else {
                Color.clear.frame(width: 8, height: 1)
            }
            Image(systemName: node.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(node.isDirectory ? Color(nsColor: .systemBlue) : RibbitTheme.muted)
                .font(.system(size: metrics.fileFontSize))
                .frame(width: 14)
            Text(node.displayName)
                .font(.system(size: metrics.fileFontSize))
                .lineLimit(1)
                .foregroundStyle(RibbitTheme.muted)
            Spacer(minLength: 0)
        }
        .frame(height: metrics.fileRowHeight)
        .contentShape(Rectangle())
    }
}
