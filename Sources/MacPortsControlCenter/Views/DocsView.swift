import SwiftUI
import AppKit

// MARK: - MarkdownStyler
public struct MarkdownStyler {
    private struct AlertType {
        let tag: String
        let icon: String
        let title: String
        let color: NSColor
    }

    private static let alertTypes: [AlertType] = [
        AlertType(tag: "[!note]", icon: "📘", title: "NOTE", color: NSColor.systemBlue),
        AlertType(tag: "[!tip]", icon: "💡", title: "TIP", color: NSColor.systemGreen),
        AlertType(tag: "[!important]", icon: "⚠️", title: "IMPORTANT", color: NSColor.systemOrange),
        AlertType(tag: "[!warning]", icon: "🛑", title: "WARNING", color: NSColor.systemRed),
        AlertType(tag: "[!caution]", icon: "🔥", title: "CAUTION", color: NSColor.systemRed)
    ]

    private static func decodeHTMLEntities(_ raw: String) -> String {
        var text = raw
        let entities = [
            ("&rarr;", "→"),
            ("&larr;", "←"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&hellip;", "…"),
            ("&copy;", "©"),
            ("&times;", "×")
        ]
        for (ent, rep) in entities {
            text = text.replacingOccurrences(of: ent, with: rep)
        }
        return text
    }

    private static func cleanCellText(_ raw: String) -> String {
        var text = decodeHTMLEntities(raw)
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        // Strip markdown links [label](url) -> label to avoid artificial URL column bloating
        if let linkRegex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\([^\\)]+\\)") {
            text = linkRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1")
        }
        text = text.replacingOccurrences(of: "**", with: "")
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func wrapText(_ text: String, width: Int) -> [String] {
        let effectiveWidth = max(4, width)
        let rawLines = text.components(separatedBy: "\n")
        var result: [String] = []

        for rawLine in rawLines {
            let words = rawLine.components(separatedBy: " ")
            var current = ""
            for word in words {
                if word.isEmpty { continue }
                if current.isEmpty {
                    if word.count <= effectiveWidth {
                        current = word
                    } else {
                        var rem = word
                        while rem.count > effectiveWidth {
                            let chunk = String(rem.prefix(effectiveWidth))
                            result.append(chunk)
                            rem = String(rem.dropFirst(effectiveWidth))
                        }
                        current = rem
                    }
                } else if current.count + 1 + word.count <= effectiveWidth {
                    current += " " + word
                } else {
                    result.append(current)
                    if word.count <= effectiveWidth {
                        current = word
                    } else {
                        var rem = word
                        while rem.count > effectiveWidth {
                            let chunk = String(rem.prefix(effectiveWidth))
                            result.append(chunk)
                            rem = String(rem.dropFirst(effectiveWidth))
                        }
                        current = rem
                    }
                }
            }
            if !current.isEmpty {
                result.append(current)
            }
        }
        return result.isEmpty ? [""] : result
    }

    private static func computeColumnWidths(rows: [[String]], numCols: Int, maxTableWidth: Int = 96) -> [Int] {
        guard numCols > 0 else { return [] }
        var minWordWidths = Array(repeating: 3, count: numCols)
        var naturalWidths = Array(repeating: 3, count: numCols)

        for row in rows {
            for (i, cell) in row.enumerated() where i < numCols {
                let words = cell.components(separatedBy: CharacterSet.whitespacesAndNewlines)
                let maxWord = words.map { $0.count }.max() ?? 0
                minWordWidths[i] = max(minWordWidths[i], min(maxWord, 24))
                naturalWidths[i] = max(naturalWidths[i], cell.count)
            }
        }

        var colWidths = naturalWidths
        let totalBorders = 3 * numCols + 3
        let availableWidth = max(40, maxTableWidth - totalBorders)
        var currentTotal = colWidths.reduce(0, +)

        while currentTotal > availableWidth {
            var bestIdx: Int? = nil
            var bestWidth = 0
            for i in 0..<numCols {
                if colWidths[i] > minWordWidths[i] && colWidths[i] > bestWidth {
                    bestWidth = colWidths[i]
                    bestIdx = i
                }
            }
            guard let idx = bestIdx, bestWidth > 12 else {
                break
            }
            colWidths[idx] -= 1
            currentTotal -= 1
        }

        return colWidths
    }

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
                    let cells = trimmed.dropFirst().dropLast().components(separatedBy: "|").map { cleanCellText($0) }
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
                let colWidths = computeColumnWidths(rows: rows, numCols: numCols)

                let tableAttr = NSMutableAttributedString()
                let pStyle = NSMutableParagraphStyle()
                pStyle.lineSpacing = 1.5
                pStyle.paragraphSpacing = 0

                for (rowIndex, row) in rows.enumerated() {
                    var cellLines: [[String]] = []
                    for (i, cell) in row.enumerated() {
                        let w = i < colWidths.count ? colWidths[i] : 20
                        cellLines.append(wrapText(cell, width: w))
                    }
                    while cellLines.count < numCols {
                        cellLines.append([""])
                    }
                    let maxLines = cellLines.map { $0.count }.max() ?? 1

                    for lineIdx in 0..<maxLines {
                        var lineStr = ""
                        for i in 0..<numCols {
                            let w = i < colWidths.count ? colWidths[i] : 20
                            let cellLine = (i < cellLines.count && lineIdx < cellLines[i].count) ? cellLines[i][lineIdx] : ""
                            let padded = cellLine.padding(toLength: w, withPad: " ", startingAt: 0)
                            lineStr += (i == 0 ? "  " : " │ ") + padded
                        }
                        lineStr += "\n"

                        let isHeader = (rowIndex == 0)
                        let font = isHeader ? NSFont.monospacedSystemFont(ofSize: 11.5, weight: .bold) : NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
                        let color = isHeader ? NSColor.controlAccentColor : NSColor.textColor
                        tableAttr.append(NSAttributedString(string: lineStr, attributes: [
                            .font: font,
                            .foregroundColor: color,
                            .paragraphStyle: pStyle
                        ]))
                    }

                    if rowIndex == 0 {
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

        func appendInlineMarkdown(_ text: String, baseFont: NSFont = NSFont.systemFont(ofSize: 13), baseColor: NSColor = NSColor.textColor, style: NSParagraphStyle) {
            let processedText = decodeHTMLEntities(text)
            if let inlineAttr = try? AttributedString(markdown: processedText, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                let mutableInline = NSMutableAttributedString(inlineAttr)
                let fullRange = NSRange(location: 0, length: mutableInline.length)
                mutableInline.addAttribute(.paragraphStyle, value: style, range: fullRange)
                mutableInline.addAttribute(.font, value: baseFont, range: fullRange)
                mutableInline.addAttribute(.foregroundColor, value: baseColor, range: fullRange)

                for run in inlineAttr.runs {
                    let nsRange = NSRange(run.range, in: inlineAttr)
                    if let inline = run.inlinePresentationIntent {
                        if inline.contains(.code) {
                            mutableInline.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: nsRange)
                            mutableInline.addAttribute(.foregroundColor, value: NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0), range: nsRange)
                            mutableInline.addAttribute(.backgroundColor, value: NSColor.black.withAlphaComponent(0.15), range: nsRange)
                        } else if inline.contains(.stronglyEmphasized) {
                            mutableInline.addAttribute(.font, value: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .bold), range: nsRange)
                        } else if inline.contains(.emphasized) {
                            mutableInline.addAttribute(.font, value: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold), range: nsRange)
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
                result.append(NSAttributedString(string: processedText + "\n", attributes: [
                    .font: baseFont,
                    .foregroundColor: baseColor,
                    .paragraphStyle: style
                ]))
            }
        }

        var activeAlert: AlertType? = nil

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
                activeAlert = nil
                tableLines.append(line)
                inTable = true
                continue
            } else if inTable {
                flushTable()
            }

            // Blockquote & GitHub Alerts
            if trimmed.hasPrefix(">") {
                let quoteContent = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)

                // Check for GitHub alert tag
                var matchedAlert: AlertType? = nil
                var alertRest = ""
                let lowerQuote = quoteContent.lowercased()
                for alert in alertTypes {
                    if lowerQuote.hasPrefix(alert.tag) {
                        matchedAlert = alert
                        alertRest = String(quoteContent.dropFirst(alert.tag.count)).trimmingCharacters(in: .whitespaces)
                        break
                    }
                }

                if let alert = matchedAlert {
                    activeAlert = alert
                    // Render alert header
                    let headerStyle = NSMutableParagraphStyle()
                    headerStyle.headIndent = 16
                    headerStyle.firstLineHeadIndent = 16
                    headerStyle.paragraphSpacingBefore = 8
                    headerStyle.paragraphSpacing = 3

                    let headerStr = "\(alert.icon) \(alert.title)\n"
                    result.append(NSAttributedString(string: headerStr, attributes: [
                        .font: NSFont.systemFont(ofSize: 12.5, weight: .bold),
                        .foregroundColor: alert.color,
                        .paragraphStyle: headerStyle
                    ]))

                    if !alertRest.isEmpty {
                        let bodyStyle = NSMutableParagraphStyle()
                        bodyStyle.headIndent = 20
                        bodyStyle.firstLineHeadIndent = 20
                        bodyStyle.lineSpacing = 3
                        bodyStyle.paragraphSpacing = 6
                        appendInlineMarkdown("┃ " + alertRest, baseFont: NSFont.systemFont(ofSize: 12.5), baseColor: NSColor.textColor, style: bodyStyle)
                    }
                    continue
                }

                // Continuation of active alert
                if activeAlert != nil {
                    let bodyStyle = NSMutableParagraphStyle()
                    bodyStyle.headIndent = 20
                    bodyStyle.firstLineHeadIndent = 20
                    bodyStyle.lineSpacing = 3
                    bodyStyle.paragraphSpacing = 6
                    appendInlineMarkdown("┃ " + quoteContent, baseFont: NSFont.systemFont(ofSize: 12.5), baseColor: NSColor.textColor, style: bodyStyle)
                    continue
                }

                // Regular blockquote
                let quoteStyle = NSMutableParagraphStyle()
                quoteStyle.headIndent = 16
                quoteStyle.firstLineHeadIndent = 16
                quoteStyle.lineSpacing = 3
                quoteStyle.paragraphSpacing = 6
                appendInlineMarkdown("┃ " + quoteContent, baseFont: NSFont.systemFont(ofSize: 12.5), baseColor: NSColor.secondaryLabelColor, style: quoteStyle)
                continue
            } else {
                activeAlert = nil
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

            // List item detection (ordered or unordered)
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            var listPrefix: String? = nil
            var listContent: String = trimmed

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                listPrefix = "• "
                listContent = String(trimmed.dropFirst(2))
            } else if let numMatch = try? NSRegularExpression(pattern: #"^(\d+\.)\s+(.*)$"#).firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) {
                let ns = trimmed as NSString
                listPrefix = ns.substring(with: numMatch.range(at: 1)) + " "
                listContent = ns.substring(with: numMatch.range(at: 2))
            }

            if let prefix = listPrefix {
                let indentLevel = max(0, leadingSpaces / 2)
                let baseIndent: CGFloat = 18.0 + CGFloat(indentLevel) * 16.0
                let firstIndent: CGFloat = max(4.0, baseIndent - 12.0)

                let listStyle = NSMutableParagraphStyle()
                listStyle.headIndent = baseIndent
                listStyle.firstLineHeadIndent = firstIndent
                listStyle.lineSpacing = 3
                listStyle.paragraphSpacing = 4

                let fullItemText = prefix + listContent
                appendInlineMarkdown(fullItemText, baseFont: NSFont.systemFont(ofSize: 13), baseColor: NSColor.textColor, style: listStyle)
                continue
            }

            // Regular paragraph
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.lineSpacing = 4
            paraStyle.paragraphSpacing = 6
            appendInlineMarkdown(line, baseFont: NSFont.systemFont(ofSize: 13), baseColor: NSColor.textColor, style: paraStyle)
        }

        flushTable()
        flushCodeBlock()
        return result
    }
}

// MARK: - DocsScrollView
public final class DocsScrollView: NSScrollView {
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupScrollers()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupScrollers()
    }

    private func setupScrollers() {
        drawsBackground = true
        backgroundColor = NSColor.textBackgroundColor
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
    }

    public override func layout() {
        super.layout()
        guard let textView = documentView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let contentWidth = contentSize.width
        guard contentWidth > 50 else { return }

        let targetWidth = contentWidth - textView.textContainerInset.width * 2
        if abs(textContainer.containerSize.width - targetWidth) > 1.0 {
            textContainer.containerSize = NSSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
            textView.frame.size.width = contentWidth
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let calculatedHeight = max(usedRect.height + textView.textContainerInset.height * 2, contentSize.height)
            textView.frame.size.height = calculatedHeight
        }
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
        var lastWidth: CGFloat = 0
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> DocsScrollView {
        let scrollView = DocsScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let initialWidth = max(200.0, contentSize.width)
        let textContainer = NSTextContainer(containerSize: NSSize(width: initialWidth, height: CGFloat.greatestFiniteMagnitude))
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
        // Do not set coordinator.currentText so updateNSView executes cleanly on initial mount
        return scrollView
    }

    public func updateNSView(_ nsView: DocsScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        let needsTextUpdate = (context.coordinator.currentText != markdownText)
        let widthChanged = (abs(context.coordinator.lastWidth - nsView.contentSize.width) > 1.0)

        if needsTextUpdate {
            let rendered = MarkdownStyler.style(markdownText)
            context.coordinator.currentText = markdownText
            context.coordinator.cachedAttributedString = rendered
            textView.textStorage?.setAttributedString(rendered)
            textView.scroll(NSPoint.zero)
        }

        if needsTextUpdate || widthChanged {
            context.coordinator.lastWidth = nsView.contentSize.width
            if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
                let contentWidth = max(100.0, nsView.contentSize.width)
                let targetWidth = contentWidth - textView.textContainerInset.width * 2
                textContainer.containerSize = NSSize(width: targetWidth, height: CGFloat.greatestFiniteMagnitude)
                textView.frame.size.width = contentWidth
                layoutManager.ensureLayout(for: textContainer)
                let usedRect = layoutManager.usedRect(for: textContainer)
                let calculatedHeight = max(usedRect.height + textView.textContainerInset.height * 2, nsView.contentSize.height)
                textView.frame.size.height = calculatedHeight
            }
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
