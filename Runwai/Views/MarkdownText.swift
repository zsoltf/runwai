import Foundation
import SwiftUI

// Foundation owns Markdown parsing. This maps its block semantics to native
// views; it never executes HTML or fetches remote images.
struct MarkdownDocument: Sendable {
    struct Block: Identifiable, Sendable {
        let id: Int
        var text: AttributedString
        var heading: Int?
        var marker: String?
        var indentation = 0
        var code = false
        var quote = false
    }
    var blocks: [Block]

    init(_ source: String) {
        guard let parsed = try? AttributedString(markdown: source) else {
            blocks = [Block(id: 0, text: AttributedString(source))]
            return
        }
        var result: [Block] = []
        for (intent, range) in parsed.runs[\.presentationIntent] {
            var block = Block(id: result.count, text: Self.safeLinks(AttributedString(parsed[range])))
            let components = intent?.components ?? []
            let ordered = components.first { $0.kind == .orderedList || $0.kind == .unorderedList }?.kind == .orderedList
            for component in components {
                switch component.kind {
                case .header(let level): block.heading = level
                case .codeBlock: block.code = true
                case .blockQuote: block.quote = true
                case .listItem(let ordinal):
                    if block.marker == nil { block.marker = ordered ? "\(ordinal)." : "\u{2022}" }
                    block.indentation += 1
                default: break
                }
            }
            result.append(block)
        }
        blocks = result
    }

    static func inline(_ source: String) -> AttributedString {
        let bounded = String(source.prefix(4096))
        var text = AttributedString()
        for block in MarkdownDocument(bounded).blocks {
            if !text.characters.isEmpty { text.append(AttributedString(" ")) }
            text.append(block.text)
        }
        // The whole preview is an expansion button, not a nested link target.
        text.link = nil
        return text
    }

    private static func safeLinks(_ source: AttributedString) -> AttributedString {
        var result = source
        for (link, range) in source.runs[\.link] {
            if let link, !["https", "http", "mailto"].contains(link.scheme?.lowercased() ?? "") {
                result[range].link = nil
            }
        }
        return result
    }
}

struct MarkdownText: View {
    let source: String
    @State private var document: MarkdownDocument?

    var body: some View {
        Group {
            if let document {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(document.blocks) { block in
                        HStack(alignment: .top, spacing: 7) {
                            if block.quote {
                                RoundedRectangle(cornerRadius: 1).fill(.secondary.opacity(0.35)).frame(width: 2)
                            }
                            if let marker = block.marker {
                                Text(marker).foregroundStyle(.secondary)
                            }
                            Text(block.text)
                                .font(block.code ? .system(size: 12, design: .monospaced) :
                                    .system(size: block.heading.map { $0 == 1 ? 19 : 16 } ?? 13,
                                            weight: block.heading == nil ? .regular : .semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .accessibilityAddTraits(block.heading == nil ? [] : .isHeader)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(block.code ? 10 : 0)
                        .padding(.leading, CGFloat(max(block.indentation - 1, 0)) * 12)
                        .background(.primary.opacity(block.code ? 0.055 : 0), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: source) {
            document = nil
            let source = source
            let parsing = Task.detached(priority: .userInitiated) { MarkdownDocument(source) }
            let result = await withTaskCancellationHandler {
                await parsing.value
            } onCancel: { parsing.cancel() }
            if !Task.isCancelled { document = result }
        }
    }
}
