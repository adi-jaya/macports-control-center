import SwiftUI
import AppKit

// MARK: - NSTextView Representable for Streamed Terminal Output
public struct TerminalTextViewRepresentable: NSViewRepresentable {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(red: 2/255.0, green: 6/255.0, blue: 23/255.0, alpha: 1.0)
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
        textView.backgroundColor = NSColor(red: 2/255.0, green: 6/255.0, blue: 23/255.0, alpha: 1.0)
        textView.textColor = NSColor(red: 226/255.0, green: 232/255.0, blue: 240/255.0, alpha: 1.0) // Slate-200
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.scrollToEndOfDocument(nil)
        }
    }
}

// MARK: - TerminalDrawerView
public struct TerminalDrawerView: View {
    @ObservedObject public var runner: CommandRunner
    @Binding public var isExpanded: Bool

    public init(runner: CommandRunner, isExpanded: Binding<Bool>) {
        self.runner = runner
        self._isExpanded = isExpanded
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                // Collapse / Expand toggle button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 11))
                        Text("Terminal Output")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                // Live status indicator
                if runner.isRunning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                        Text(runner.currentCommandLabel.isEmpty ? "Executing..." : runner.currentCommandLabel)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.accentColor)
                            .lineLimit(1)
                    }
                } else if !runner.terminalLines.isEmpty {
                    Text("\(runner.terminalLines.count) lines")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Cancel process button
                if runner.isRunning {
                    Button(action: {
                        runner.cancelCurrentProcess()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.circle.fill")
                            Text("Cancel Process")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }

                // Clear log button
                Button(action: {
                    runner.clearLog()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(runner.terminalLines.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .top
            )

            // Streamed Output Body
            if isExpanded {
                TerminalTextViewRepresentable(text: runner.terminalLines.joined(separator: "\n"))
                    .frame(minHeight: 120, maxHeight: 220)
                    .background(Color(red: 2/255.0, green: 6/255.0, blue: 23/255.0))
            }
        }
    }
}
