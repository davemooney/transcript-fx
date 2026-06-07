import SwiftUI

/// Per-glyph diff-morph using the Text Renderer API (the upgrade over the
/// word-level `contentTransition` in RevisingText). Only the glyphs in the
/// changed range animate in (blur + rise + fade); the rest draw normally.
@available(iOS 18.0, macOS 15.0, *)
struct DiffMorphRenderer: TextRenderer {
    var progress: Double
    var animatedGlyphs: Set<Int>

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var index = 0
        for line in layout {
            for run in line {
                for glyph in run {
                    var glyphContext = context
                    if animatedGlyphs.contains(index) {
                        let p = max(0, min(1, progress))
                        glyphContext.opacity = p
                        glyphContext.translateBy(x: 0, y: (1 - p) * 6)
                        glyphContext.addFilter(.blur(radius: (1 - p) * 4))
                    }
                    glyphContext.draw(glyph)
                    index += 1
                }
            }
        }
    }
}

/// Drop-in replacement for a token's text that morphs only the changed glyphs.
@available(iOS 18.0, macOS 15.0, *)
public struct GlyphDiffText: View {
    public let text: String
    public var font: Font

    @State private var progress: Double = 1
    @State private var animatedGlyphs: Set<Int> = []
    @State private var previous = ""

    public init(_ text: String, font: Font = .system(size: 24)) {
        self.text = text
        self.font = font
    }

    public var body: some View {
        Text(text)
            .font(font)
            .textRenderer(DiffMorphRenderer(progress: progress, animatedGlyphs: animatedGlyphs))
            .onAppear { previous = text }
            .onChange(of: text) { _, newValue in
                animatedGlyphs = Set(changedGlyphRange(previous, newValue))
                previous = newValue
                progress = 0
                withAnimation(.easeOut(duration: 0.45)) { progress = 1 }
            }
    }
}

/// Indices (≈ character positions) of the changed middle: longest common
/// prefix/suffix removed. Mirrors the web `diffParts`.
func changedGlyphRange(_ a: String, _ b: String) -> Range<Int> {
    let ac = Array(a)
    let bc = Array(b)
    var p = 0
    let maxP = min(ac.count, bc.count)
    while p < maxP && ac[p] == bc[p] { p += 1 }
    var s = 0
    let maxS = min(ac.count - p, bc.count - p)
    while s < maxS && ac[ac.count - 1 - s] == bc[bc.count - 1 - s] { s += 1 }
    let end = bc.count - s
    return p < end ? p..<end : 0..<0
}
