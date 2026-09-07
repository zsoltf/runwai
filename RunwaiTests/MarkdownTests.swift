import Foundation
import Testing
@testable import runwai

struct MarkdownTests {
    @Test
    func nativeBlocksPreserveContentAndFormatting() {
        let document = MarkdownDocument("""
        # Progress

        A **bold** move with `code`.

        1. First step
        2. Second step

        > A caveat

        ```swift
        let complete = true
        ```
        """)
        #expect(document.blocks.count == 6)
        #expect(document.blocks.first?.heading == 1)
        #expect(document.blocks[2].marker == "1.")
        #expect(document.blocks[3].marker == "2.")
        #expect(document.blocks[4].quote)
        #expect(document.blocks[5].code)
        #expect(String(document.blocks[5].text.characters).contains("let complete = true"))
        #expect(document.blocks[1].text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(document.blocks[1].text.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
    }

    @Test
    func previewsParseInlineMarkdownWithoutNestedLinks() {
        let preview = MarkdownDocument.inline("A **clear** [answer](https://example.com) with `code`.")
        #expect(String(preview.characters) == "A clear answer with code.")
        #expect(preview.runs.allSatisfy { $0.link == nil })
        #expect(String(MarkdownDocument.inline("## A heading").characters) == "A heading")
        #expect(String(MarkdownDocument.inline("# Result\n\nAll checks pass.").characters) == "Result All checks pass.")
        #expect(String(MarkdownDocument.inline("```swift\nlet ready = true\n```").characters).contains("let ready = true"))
    }

    @Test
    func originalLinksDoNotLaunchCustomSchemes() {
        let document = MarkdownDocument("[web](https://example.com) [local](file:///tmp/run) [action](shell:run)")
        let links = document.blocks.flatMap { $0.text.runs.compactMap(\.link) }
        #expect(links == [URL(string: "https://example.com")!])
        #expect(String(document.blocks[0].text.characters) == "web local action")
    }
}
