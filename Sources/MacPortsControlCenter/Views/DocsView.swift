import SwiftUI
import AppKit

// MARK: - MarkdownStyler
public struct MarkdownStyler {
    public static func style(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeLines = [String]()
        var inTable = false
        var tableLines = [String]()

        func flushTable() {
            guard !tableLines.isEmpty else { return }
            var rows: [[String]] = []
            for line in tableLines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                    let cells = trimmed.dropFirst().dropLast().components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    let isSep = cells.allSatisfy { cell in
                        cell.allSatisfy { $0 == "-" || $0 == ":" } && !cell.isEmpty
                    }
                    if !isSep {
                        rows.append(cells)
                    }
                }
            }
            if !rows.isEmpty {
                let numCols = rows.map { $0.count }.max() ?? 0
                var colWidths = Array(repeating: 0, count: numCols)
                for row in rows {
                    for (i, cell) in row.enumerated() {
                        if i < numCols {
                            colWidths[i] = max(colWidths[i], cell.count)
                        }
                    }
                }

                let tableAttr = NSMutableAttributedString()
                let pStyle = NSMutableParagraphStyle()
                pStyle.lineSpacing = 2
                pStyle.paragraphSpacing = 0

                for (rowIndex, row) in rows.enumerated() {
                    var lineStr = ""
                    for (i, cell) in row.enumerated() {
                        let w = colWidths[i]
                        let padded = cell.padding(toLength: w, withPad: " ", startingAt: 0)
                        lineStr += (i == 0 ? "  " : " │ ") + padded
                    }
                    lineStr += "\n"

                    let isHeader = (rowIndex == 0)
                    let font = isHeader ? NSFont.monospacedSystemFont(ofSize: 11.5, weight: .bold) : NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
                    let color = isHeader ? NSColor.controlAccentColor : NSColor.textColor
                    let rowAttr = NSAttributedString(string: lineStr, attributes: [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: pStyle
                    ])
                    tableAttr.append(rowAttr)

                    if isHeader {
                        var sepStr = "  "
                        for (i, w) in colWidths.enumerated() {
                            sepStr += (i == 0 ? "" : "─┼─") + String(repeating: "─", count: w)
                        }
                        sepStr += "\n"
                        tableAttr.append(NSAttributedString(string: sepStr, attributes: [
                            .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
                            .foregroundColor: NSColor.secondaryLabelColor,
                            .paragraphStyle: pStyle
                        ]))
                    }
                }
                tableAttr.append(NSAttributedString(string: "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 6),
                    .paragraphStyle: pStyle
                ]))
                result.append(tableAttr)
            }
            tableLines.removeAll()
            inTable = false
        }

        func flushCodeBlock() {
            guard inCodeBlock else { return }
            let codeText = codeLines.joined(separator: "\n") + "\n"
            let codeStyle = NSMutableParagraphStyle()
            codeStyle.lineSpacing = 3
            codeStyle.paragraphSpacing = 8
            codeStyle.headIndent = 16
            codeStyle.firstLineHeadIndent = 16

            let codeAttr = NSAttributedString(string: codeText, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0),
                .backgroundColor: NSColor.black.withAlphaComponent(0.2),
                .paragraphStyle: codeStyle
            ])
            result.append(codeAttr)
            codeLines.removeAll()
            inCodeBlock = false
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code block delimiter
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    flushCodeBlock()
                } else {
                    flushTable()
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            // Table detection
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                tableLines.append(line)
                inTable = true
                continue
            } else if inTable {
                flushTable()
            }

            // Headings
            if trimmed.hasPrefix("#") {
                var level = 0
                for char in trimmed {
                    if char == "#" { level += 1 } else { break }
                }
                if level > 0 && trimmed.count > level && trimmed[trimmed.index(trimmed.startIndex, offsetBy: level)] == " " {
                    let headingText = String(trimmed.dropFirst(level + 1))
                    let fontSize: CGFloat = level == 1 ? 22 : (level == 2 ? 18 : (level == 3 ? 15 : 13.5))
                    let headingStyle = NSMutableParagraphStyle()
                    headingStyle.paragraphSpacing = 8
                    headingStyle.paragraphSpacingBefore = (level == 1 ? 8 : 16)
                    let headingColor: NSColor = (level == 1) ? .controlAccentColor : .textColor

                    result.append(NSAttributedString(string: headingText + "\n", attributes: [
                        .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                        .foregroundColor: headingColor,
                        .paragraphStyle: headingStyle
                    ]))
                    continue
                }
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                let ruleStyle = NSMutableParagraphStyle()
                ruleStyle.paragraphSpacing = 12
                ruleStyle.paragraphSpacingBefore = 8
                result.append(NSAttributedString(string: "──────────────────────────────────────────────────────\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.separatorColor,
                    .paragraphStyle: ruleStyle
                ]))
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                let quoteText = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                let quoteStyle = NSMutableParagraphStyle()
                quoteStyle.headIndent = 16
                quoteStyle.firstLineHeadIndent = 16
                quoteStyle.lineSpacing = 3
                quoteStyle.paragraphSpacing = 6
                result.append(NSAttributedString(string: "┃ " + quoteText + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 12.5),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: quoteStyle
                ]))
                continue
            }

            // Blank line
            if trimmed.isEmpty {
                let blankStyle = NSMutableParagraphStyle()
                blankStyle.paragraphSpacing = 6
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 6),
                    .paragraphStyle: blankStyle
                ]))
                continue
            }

            // Regular paragraph or list item with inline markdown formatting
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.lineSpacing = 4
            paraStyle.paragraphSpacing = 6
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                paraStyle.headIndent = 20
                paraStyle.firstLineHeadIndent = 8
            }

            let lineToFormat = line
            if let inlineAttr = try? AttributedString(markdown: lineToFormat, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                let mutableInline = NSMutableAttributedString(inlineAttr)
                let fullRange = NSRange(location: 0, length: mutableInline.length)
                mutableInline.addAttribute(.paragraphStyle, value: paraStyle, range: fullRange)
                mutableInline.addAttribute(.font, value: NSFont.systemFont(ofSize: 13), range: fullRange)
                mutableInline.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)

                for run in inlineAttr.runs {
                    let nsRange = NSRange(run.range, in: inlineAttr)
                    if let inline = run.inlinePresentationIntent {
                        if inline.contains(.code) {
                            mutableInline.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: nsRange)
                            mutableInline.addAttribute(.foregroundColor, value: NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0), range: nsRange)
                            mutableInline.addAttribute(.backgroundColor, value: NSColor.black.withAlphaComponent(0.15), range: nsRange)
                        } else if inline.contains(.stronglyEmphasized) {
                            mutableInline.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .bold), range: nsRange)
                        } else if inline.contains(.emphasized) {
                            mutableInline.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .semibold), range: nsRange)
                        }
                    }
                    if let url = run.link {
                        mutableInline.addAttribute(.link, value: url, range: nsRange)
                        mutableInline.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: nsRange)
                        mutableInline.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
                    }
                }
                result.append(mutableInline)
                result.append(NSAttributedString(string: "\n"))
            } else {
                result.append(NSAttributedString(string: line + "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.textColor,
                    .paragraphStyle: paraStyle
                ]))
            }
        }

        flushTable()
        flushCodeBlock()
        return result
    }
}

// MARK: - MarkdownTextViewRepresentable
public struct MarkdownTextViewRepresentable: NSViewRepresentable {
    public let markdownText: String

    public init(markdownText: String) {
        self.markdownText = markdownText
    }

    public class Coordinator {
        var currentText: String = ""
        var cachedAttributedString: NSAttributedString?
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
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
        textView.textContainerInset = NSSize(width: 28, height: 28)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        let rendered = MarkdownStyler.style(markdownText)
        context.coordinator.currentText = markdownText
        context.coordinator.cachedAttributedString = rendered
        textView.textStorage?.setAttributedString(rendered)
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if context.coordinator.currentText != markdownText {
            let rendered = MarkdownStyler.style(markdownText)
            context.coordinator.currentText = markdownText
            context.coordinator.cachedAttributedString = rendered
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
