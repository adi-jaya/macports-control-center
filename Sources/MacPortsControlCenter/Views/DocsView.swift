import SwiftUI
import AppKit

// MARK: - MarkdownStyler
public struct MarkdownStyler {
    public static func style(_ markdown: String) -> NSAttributedString {
        if let attr = try? AttributedString(markdown: markdown, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)) {
            let mutable = NSMutableAttributedString(attr)

            // Ensure comfortable base line spacing and font hierarchy
            let fullRange = NSRange(location: 0, length: mutable.length)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.paragraphSpacing = 10
            mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

            return mutable
        }

        // Fallback plain rendering
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 10
        return NSAttributedString(string: markdown, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ])
    }
}

// MARK: - MarkdownTextViewRepresentable
public struct MarkdownTextViewRepresentable: NSViewRepresentable {
    public let markdownText: String

    public init(markdownText: String) {
        self.markdownText = markdownText
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        let rendered = MarkdownStyler.style(markdownText)
        textView.textStorage?.setAttributedString(rendered)
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let rendered = MarkdownStyler.style(markdownText)
        if textView.textStorage?.string != rendered.string {
            textView.textStorage?.setAttributedString(rendered)
            textView.scroll(NSPoint.zero)
        }
    }
}

// MARK: - DocsView
public struct DocsView: View {
    @EnvironmentObject public var appState: AppState

    @State private var docSearchQuery: String = ""
    @State private var feedbackMessage: String? = nil

    public init() {}

    private var filteredDocs: [DocItem] {
        let trimmed = docSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return appState.docFiles
        }
        return appState.docFiles.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
            $0.fileName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left Docs Navigator Sidebar
            docsListSidebar
                .frame(width: 260)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Right Markdown Reader Content Area
            VStack(spacing: 0) {
                if let currentDoc = appState.selectedDoc {
                    // Document Header
                    docHeaderView(doc: currentDoc)

                    Divider()

                    // Notification Banner
                    if let feedback = feedbackMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(feedback)
                                .font(.system(size: 11))
                            Spacer()
                            Button("Dismiss") { feedbackMessage = nil }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12))
                    }

                    // Native Markdown Reader (NSTextView)
                    MarkdownTextViewRepresentable(markdownText: appState.selectedDocContent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No Document Selected")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .onAppear {
            if appState.selectedDoc == nil, let first = appState.docFiles.first {
                appState.selectDoc(first)
            }
        }
    }

    // MARK: - Docs List Sidebar
    private var docsListSidebar: some View {
        VStack(spacing: 0) {
            // Sidebar Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "books.vertical.fill")
                        .foregroundColor(.accentColor)
                    Text("Documentation")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Button(action: {
                        appState.loadDocumentationFiles()
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("Rescan Markdown files in repository")
                }

                // Search Box
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField("Filter guides...", text: $docSearchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !docSearchQuery.isEmpty {
                        Button(action: { docSearchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
            .padding(12)

            Divider()

            // Documents Scroll List
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(filteredDocs) { doc in
                        let isSelected = (appState.selectedDoc?.id == doc.id)
                        Button(action: {
                            appState.selectDoc(doc)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: docIcon(for: doc.fileName))
                                    .font(.system(size: 12))
                                    .frame(width: 16)
                                    .foregroundColor(isSelected ? .white : .accentColor)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(doc.title)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .lineLimit(1)
                                    Text(doc.fileName)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(isSelected ? Color.accentColor : Color.clear)
                        .cornerRadius(6)
                    }
                }
                .padding(8)
            }
        }
    }

    private func docIcon(for fileName: String) -> String {
        switch fileName {
        case "README.md": return "doc.text.fill"
        case "AGENTS.md": return "cpu"
        case "VIRTUAL_HOSTS_AND_DOMAINS_GUIDE.md": return "globe"
        case "FRESH_INSTALL_GUIDE.md": return "sparkles"
        case "FINAL_MACPORTS_ENVIRONMENT_SETUP.md": return "checklist"
        case "HANDOFF_MACPORTS_MIGRATION.md": return "arrow.triangle.pull"
        default: return "doc.text"
        }
    }

    // MARK: - Document Header
    private func docHeaderView(doc: DocItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title)
                    .font(.system(size: 15, weight: .bold))

                HStack(spacing: 6) {
                    Text(doc.filePath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.selectedDocContent, forType: .string)
                    feedbackMessage = "Copied '\(doc.fileName)' to clipboard."
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: {
                    NSWorkspace.shared.selectFile(doc.filePath, inFileViewerRootedAtPath: (doc.filePath as NSString).deletingLastPathComponent)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("Reveal in Finder")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: {
                    NSWorkspace.shared.open(URL(fileURLWithPath: doc.filePath))
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
