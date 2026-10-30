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

    private struct CacheEntry {
        let length: Int
        let hash: Int
        let rendered: NSAttributedString
    }

    private static let cacheLock = NSLock()
    private static var cache: [String: CacheEntry] = [:]

    private static let alertTypes: [AlertType] = [
        AlertType(tag: "[!note]", icon: "📘", title: "NOTE", color: NSColor.systemBlue),
        AlertType(tag: "[!tip]", icon: "💡", title: "TIP", color: NSColor.systemGreen),
        AlertType(tag: "[!important]", icon: "⚠️", title: "IMPORTANT", color: NSColor.systemOrange),
        AlertType(tag: "[!warning]", icon: "🛑", title: "WARNING", color: NSColor.systemRed),
        AlertType(tag: "[!caution]", icon: "🔥", title: "CAUTION", color: NSColor.systemRed)
    ]

    private static let orderedListRegex = try! NSRegularExpression(pattern: #"^(\d+\.)\s+(.*)$"#)
    private static let brTagRegex = try! NSRegularExpression(pattern: #"<br\s*/?>"#, options: [.caseInsensitive])

    public static func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache.removeAll()
    }

    public static func cachedStyle(for key: String, markdown: String) -> NSAttributedString {
        let length = markdown.utf8.count
        let hash = markdown.hashValue

        cacheLock.lock()
        if let entry = cache[key], entry.length == length, entry.hash == hash {
            let rendered = entry.rendered
            cacheLock.unlock()
            return rendered
        }
        cacheLock.unlock()

        let rendered = style(markdown)

        cacheLock.lock()
        cache[key] = CacheEntry(length: length, hash: hash, rendered: rendered)
        cacheLock.unlock()

        return rendered
    }

    private static func decodeHTMLEntities(_ raw: String) -> String {
        guard raw.contains("&") else { return raw }
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
        if text.contains("<") {
            let mutable = NSMutableString(string: text)
            brTagRegex.replaceMatches(in: mutable, range: NSRange(location: 0, length: mutable.length), withTemplate: "\n")
            text = mutable as String
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func hasInlineSyntax(_ s: String) -> Bool {
        s.utf8.contains { $0 == 96 || $0 == 42 || $0 == 95 || $0 == 91 || $0 == 126 || $0 == 92 }
    }

    private static func computePercentages(rows: [[String]], numCols: Int) -> [CGFloat] {
        guard numCols > 0 else { return [] }
        var colWeights: [CGFloat] = Array(repeating: 5.0, count: numCols)
        for row in rows {
            for (i, cell) in row.enumerated() where i < numCols {
                let len = CGFloat(cell.count)
                colWeights[i] = max(colWeights[i], min(len, 60.0))
            }
        }
        let minPct: CGFloat = numCols > 4 ? 8.0 : 12.0
        var colPcts = colWeights
        let sumWeights = colPcts.reduce(0, +)
        for i in 0..<numCols {
            colPcts[i] = max(minPct, round((colWeights[i] / sumWeights) * 100.0))
        }
        let currentSum = colPcts.reduce(0, +)
        let diff = 100.0 - currentSum
        if let maxIdx = colPcts.indices.max(by: { colPcts[$0] < colPcts[$1] }) {
            colPcts[maxIdx] += diff
        }
        return colPcts
    }

    public static func style(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeLines = [String]()
        var inTable = false
        var tableLines = [String]()

        func formatCellMarkdown(_ text: String, baseFont: NSFont, baseColor: NSColor, style: NSParagraphStyle) -> NSAttributedString {
            let processed = decodeHTMLEntities(text)
            guard hasInlineSyntax(processed) else {
                return NSAttributedString(string: (processed.isEmpty ? " " : processed) + "\n", attributes: [
                    .font: baseFont,
                    .foregroundColor: baseColor,
                    .paragraphStyle: style
                ])
            }
            if let inlineAttr = try? AttributedString(markdown: processed, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                let mutable = NSMutableAttributedString(inlineAttr)
                let fullRange = NSRange(location: 0, length: mutable.length)
                mutable.addAttribute(.paragraphStyle, value: style, range: fullRange)
                mutable.addAttribute(.font, value: baseFont, range: fullRange)
                mutable.addAttribute(.foregroundColor, value: baseColor, range: fullRange)

                for run in inlineAttr.runs {
                    let nsRange = NSRange(run.range, in: inlineAttr)
                    if let inline = run.inlinePresentationIntent {
                        if inline.contains(.code) {
                            mutable.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium), range: nsRange)
                            mutable.addAttribute(.foregroundColor, value: NSColor(calibratedRed: 0.22, green: 0.74, blue: 0.97, alpha: 1.0), range: nsRange)
                            mutable.addAttribute(.backgroundColor, value: NSColor.black.withAlphaComponent(0.18), range: nsRange)
                        } else if inline.contains(.stronglyEmphasized) {
                            mutable.addAttribute(.font, value: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .bold), range: nsRange)
                        } else if inline.contains(.emphasized) {
                            mutable.addAttribute(.font, value: NSFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold), range: nsRange)
                        }
                    }
                    if let url = run.link {
                        mutable.addAttribute(.link, value: url, range: nsRange)
                        mutable.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: nsRange)
                        mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nsRange)
                    }
                }
                mutable.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
                return mutable
            } else {
                return NSAttributedString(string: (processed.isEmpty ? " " : processed) + "\n", attributes: [
                    .font: baseFont,
                    .foregroundColor: baseColor,
                    .paragraphStyle: style
                ])
            }
        }

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
                guard numCols > 0 else {
                    tableLines.removeAll()
                    inTable = false
                    return
                }

                let colPercentages = computePercentages(rows: rows, numCols: numCols)

                let table = NSTextTable()
                table.numberOfColumns = numCols
                table.collapsesBorders = true
                table.setValue(100.0, type: .percentageValueType, for: .width)

                let tableAttr = NSMutableAttributedString()

                for (rowIndex, row) in rows.enumerated() {
                    let isHeader = (rowIndex == 0)
                    for colIndex in 0..<numCols {
                        let cellContent = colIndex < row.count ? row[colIndex] : ""
                        let block = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1, startingColumn: colIndex, columnSpan: 1)

                        block.setWidth(10.0, type: .absoluteValueType, for: .padding, edge: .minX)
                        block.setWidth(10.0, type: .absoluteValueType, for: .padding, edge: .maxX)
                        block.setWidth(6.0, type: .absoluteValueType, for: .padding, edge: .minY)
                        block.setWidth(6.0, type: .absoluteValueType, for: .padding, edge: .maxY)

                        block.setWidth(0.5, type: .absoluteValueType, for: .border, edge: .minX)
                        block.setWidth(0.5, type: .absoluteValueType, for: .border, edge: .maxX)
                        block.setWidth(0.5, type: .absoluteValueType, for: .border, edge: .minY)
                        block.setWidth(0.5, type: .absoluteValueType, for: .border, edge: .maxY)

                        block.setBorderColor(NSColor.separatorColor)

                        if isHeader {
                            block.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14)
                        } else if rowIndex % 2 == 1 {
                            block.backgroundColor = NSColor.textColor.withAlphaComponent(0.035)
                        } else {
                            block.backgroundColor = NSColor.clear
                        }

                        if colIndex < colPercentages.count {
                            block.setValue(colPercentages[colIndex], type: .percentageValueType, for: .width)
                        }

                        let pStyle = NSMutableParagraphStyle()
                        pStyle.textBlocks = [block]
                        pStyle.lineSpacing = 3
                        pStyle.paragraphSpacing = 0

                        let baseFont = isHeader ? NSFont.systemFont(ofSize: 12.5, weight: .bold) : NSFont.systemFont(ofSize: 12)
                        let baseColor = isHeader ? NSColor.controlAccentColor : NSColor.textColor

                        let cellAttr = formatCellMarkdown(cellContent, baseFont: baseFont, baseColor: baseColor, style: pStyle)
                        tableAttr.append(cellAttr)
                    }
                }

                let afterTableStyle = NSMutableParagraphStyle()
                afterTableStyle.paragraphSpacing = 8
                tableAttr.append(NSAttributedString(string: "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 6),
                    .paragraphStyle: afterTableStyle
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
            guard hasInlineSyntax(processedText) else {
                result.append(NSAttributedString(string: processedText + "\n", attributes: [
                    .font: baseFont,
                    .foregroundColor: baseColor,
                    .paragraphStyle: style
                ]))
                return
            }
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
            } else if let numMatch = orderedListRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) {
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
    public let docKey: String
    public let markdownText: String

    public init(docKey: String = "inline", markdownText: String) {
        self.docKey = docKey
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
            let rendered = MarkdownStyler.cachedStyle(for: docKey, markdown: markdownText)
            context.coordinator.currentText = markdownText
            context.coordinator.cachedAttributedString = rendered
            textView.textStorage?.setAttributedString(rendered)
            textView.scroll(NSPoint.zero)
        }

        if widthChanged {
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
                    MarkdownTextViewRepresentable(
                        docKey: currentDoc.filePath,
                        markdownText: appState.selectedDocContent
                    )
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
            appState.ensureSelectedDocLoaded()
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
