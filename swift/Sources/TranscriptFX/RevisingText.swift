import SwiftUI

/// Renders a live, self-revising transcript. Conforms to SPEC.md §3:
/// ink-settle base · diff-morph corrections (word-level v1) · swipe redactions · correction flash.
public struct RevisingText: View {
    public var tokens: [Token]
    public var baseFontSize: CGFloat

    public init(tokens: [Token], baseFontSize: CGFloat = 24) {
        self.tokens = tokens
        self.baseFontSize = baseFontSize
    }

    public var body: some View {
        FlowLayout(spacing: 7, lineSpacing: 10) {
            ForEach(tokens) { token in
                TokenView(token: token, baseFontSize: baseFontSize)
            }
        }
    }
}

private struct TokenView: View {
    let token: Token
    let baseFontSize: CGFloat

    @State private var flash = false
    @State private var lastText = ""

    // Ink-settle: confidence + state → weight + opacity. (Spec §3)
    private var weight: Font.Weight {
        if token.isFinal { return .semibold }
        return token.isLowConfidence ? .ultraLight : .light
    }
    private var textOpacity: Double {
        if token.isFinal { return 1 }
        return token.isLowConfidence ? 0.42 : 0.6
    }

    var body: some View {
        Group {
            if token.redacted {
                RedactionBlock(text: token.text, fontSize: baseFontSize)
            } else {
                Text(token.text)
                    .font(.system(size: baseFontSize, weight: weight))
                    .opacity(textOpacity)
                    .contentTransition(.numericText()) // word-level morph; Text Renderer = per-glyph upgrade
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(flash ? 0.45 : 0))
                            .padding(-3)
                    )
            }
        }
        .animation(.smooth(duration: 0.45), value: token.state)
        .animation(.snappy(duration: 0.35), value: token.text)
        .animation(.easeOut(duration: 0.9), value: flash)
        .onAppear { lastText = token.text }
        .onChange(of: token.text) { _, newValue in
            guard !token.redacted, !lastText.isEmpty, lastText != newValue else {
                lastText = newValue
                return
            }
            lastText = newValue
            flash = true
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                flash = false
            }
        }
    }
}

/// A solid green block sized to the word, with a brighter band sweeping across. (Spec §3)
private struct RedactionBlock: View {
    let text: String
    let fontSize: CGFloat
    @State private var sweep = false

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .opacity(0) // reserve the original word's width
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 0.20, green: 0.83, blue: 0.60))
                    .overlay(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.55), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 34)
                        .offset(x: sweep ? 70 : -70)
                        .blendMode(.plusLighter)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(.vertical, -1)
                    .padding(.horizontal, -3)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6)) { sweep = true }
            }
    }
}

#if DEBUG
#Preview {
    TranscriptFXPreviewHost()
        .frame(width: 560, height: 360)
        .background(Color.black)
}

private struct TranscriptFXPreviewHost: View {
    @StateObject private var model = TranscriptModel()
    var body: some View {
        RevisingText(tokens: model.tokens, baseFontSize: 24)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task { await playSampleLoop(model) }
    }
}

@MainActor
private func playSampleLoop(_ m: TranscriptModel) async {
    func wait(_ ms: UInt64) async -> Bool {
        try? await Task.sleep(for: .milliseconds(ms))
        return Task.isCancelled
    }
    while !Task.isCancelled {
        m.clear()
        if await wait(500) { return }
        m.append("1", "okay", confidence: 0.95); if await wait(180) { return }
        m.append("2", "so", confidence: 0.9); if await wait(180) { return }
        m.append("3", "the", confidence: 0.95); if await wait(180) { return }
        m.append("4", "cue", confidence: 0.4); if await wait(180) { return }
        m.append("5", "deck", confidence: 0.85); if await wait(180) { return }
        m.revise("4", "Q3"); if await wait(650) { return }
        m.append("6", "for", confidence: 0.9); if await wait(180) { return }
        m.append("7", "Acme", confidence: 0.5); if await wait(180) { return }
        m.append("8", "is", confidence: 0.9); if await wait(180) { return }
        m.append("9", "to", confidence: 0.4); if await wait(180) { return }
        m.append("10", "weeks", confidence: 0.9); if await wait(700) { return }
        m.revise("9", "two"); if await wait(900) { return }
        m.redact("7"); if await wait(1100) { return }
        m.finalizeAll(); if await wait(3000) { return }
    }
}
#endif
