import SwiftUI

/// How the transcript is presented.
public enum RenderingMode: Sendable {
    /// Raw live feed: ink-settle styling and a caret, no revision flashes.
    case livePreview
    /// The full signature: live feed plus in-place revision morphs with a
    /// brief flash so corrections stay legible. The default.
    case liveRevision
    /// Finalized tokens only, full ink, no motion — the settled document.
    case finalText
    /// Diagnostic chrome: state borders, tier/confidence captions,
    /// sentence/paragraph boundary markers.
    case debug
}

/// Renders a `TranscriptSnapshot` as speaker-attributed paragraphs of
/// animated word tokens. Pure: give it the latest snapshot and it handles
/// every transition — words settling, corrections morphing in place,
/// sentences and paragraphs forming.
///
///     TranscriptView(snapshot: session.snapshot)
///     TranscriptView(snapshot: session.snapshot, mode: .finalText, theme: myTheme)
public struct TranscriptView: View {
    public var snapshot: TranscriptSnapshot
    public var mode: RenderingMode
    public var theme: TranscriptTheme

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    public init(
        snapshot: TranscriptSnapshot,
        mode: RenderingMode = .liveRevision,
        theme: TranscriptTheme = .default
    ) {
        self.snapshot = snapshot
        self.mode = mode
        self.theme = theme
    }

    private var motion: Bool { !(theme.reduceMotion ?? systemReduceMotion) }

    public var body: some View {
        let paragraphs = displayParagraphs
        VStack(alignment: .leading, spacing: theme.paragraphSpacing) {
            ForEach(paragraphs) { paragraph in
                ParagraphView(
                    paragraph: paragraph,
                    showsCaret: mode != .finalText && snapshot.isLive && paragraph.id == paragraphs.last?.id,
                    mode: mode,
                    theme: theme,
                    motion: motion
                )
                .transition(motion
                    ? .asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity)
                    : .identity)
            }
        }
        .animation(motion ? .smooth(duration: theme.settleDuration) : nil, value: paragraphs.map(\.id))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayParagraphs: [TranscriptParagraph] {
        guard mode == .finalText else { return snapshot.paragraphs }
        return snapshot.paragraphs.compactMap { p in
            let sentences = p.sentences.compactMap { s -> TranscriptSentence? in
                let tokens = s.tokens.filter(\.isFinalized)
                return tokens.isEmpty ? nil : TranscriptSentence(id: s.id, tokens: tokens)
            }
            return sentences.isEmpty ? nil : TranscriptParagraph(id: p.id, speaker: p.speaker, sentences: sentences)
        }
    }
}

// MARK: - Paragraph

private struct ParagraphView: View {
    let paragraph: TranscriptParagraph
    let showsCaret: Bool
    let mode: RenderingMode
    let theme: TranscriptTheme
    let motion: Bool

    var body: some View {
        let style = theme.speakerStyle(paragraph.speaker)
        VStack(alignment: .leading, spacing: 6) {
            if theme.showSpeakerLabels, let label = style.label {
                Text(label)
                    .font(.system(size: max(11, theme.baseFontSize * 0.5), weight: .bold))
                    .foregroundStyle(style.color)
                    .opacity(paragraph.isSettled || mode == .finalText ? 1 : 0.75)
            }
            FlowLayout(spacing: theme.wordSpacing, lineSpacing: theme.lineSpacing) {
                ForEach(paragraph.sentences) { sentence in
                    ForEach(sentence.tokens) { token in
                        TokenView(
                            token: token,
                            mode: mode,
                            theme: theme,
                            speakerColor: theme.colorizeSpeakerText ? theme.speakerStyle(token.speaker).color : nil,
                            motion: motion
                        )
                        .transition(motion ? .opacity : .identity)
                    }
                    if mode == .debug {
                        Text("·s")
                            .font(.system(size: theme.baseFontSize * 0.45, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                if showsCaret {
                    CaretView(height: theme.baseFontSize * 1.05, motion: motion)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if mode == .debug {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style.color.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .padding(-6)
            }
        }
    }
}

// MARK: - Token

private struct TokenView: View {
    let token: TranscriptToken
    let mode: RenderingMode
    let theme: TranscriptTheme
    let speakerColor: Color?
    let motion: Bool

    @State private var flash = false

    private var isLowConfidence: Bool {
        (token.confidence ?? 1) < theme.confidenceThreshold
    }

    // Ink-settle: lifecycle state + confidence → weight + opacity.
    private var weight: Font.Weight {
        guard mode != .finalText else { return theme.finalizedWeight }
        switch token.state {
        case .finalized: return theme.finalizedWeight
        case .revised: return theme.revisedWeight
        case .provisional: return isLowConfidence ? theme.lowConfidenceWeight : theme.provisionalWeight
        }
    }

    private var textOpacity: Double {
        guard mode != .finalText else { return 1 }
        switch token.state {
        case .finalized: return 1
        case .revised: return theme.revisedOpacity
        case .provisional: return isLowConfidence ? theme.lowConfidenceOpacity : theme.provisionalOpacity
        }
    }

    var body: some View {
        if mode == .debug {
            debugBody
        } else {
            textBody
        }
    }

    private var textBody: some View {
        Text(token.text)
            .font(.system(size: theme.baseFontSize, weight: weight, design: theme.fontDesign))
            .foregroundStyle(speakerColor ?? .primary)
            .opacity(textOpacity)
            .contentTransition(motion ? .numericText() : .identity)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.revisionFlashColor.opacity(flash ? 0.4 : 0))
                    .padding(-3)
            )
            .animation(motion ? .smooth(duration: theme.settleDuration) : nil, value: token.state)
            .animation(motion ? .snappy(duration: theme.revisionDuration) : nil, value: token.text)
            .animation(motion ? .easeOut(duration: theme.flashDuration) : nil, value: flash)
            .onChange(of: token.revision) { _, _ in
                guard mode == .liveRevision, motion else { return }
                flash = true
                Task {
                    try? await Task.sleep(for: .seconds(theme.flashDuration))
                    flash = false
                }
            }
    }

    private var stateColor: Color {
        switch token.state {
        case .provisional: return .gray
        case .revised: return .indigo
        case .finalized: return .green
        }
    }

    private var debugBody: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(token.text)
                .font(.system(size: theme.baseFontSize * 0.8, weight: weight, design: theme.fontDesign))
            Text("\(token.id) \(token.tier == .preview ? "p" : "r")\(token.confidence.map { String(format: " %.2f", $0) } ?? "")")
                .font(.system(size: max(8, theme.baseFontSize * 0.32), design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(3)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(stateColor.opacity(0.6), lineWidth: 1))
    }
}

// MARK: - Caret

private struct CaretView: View {
    let height: CGFloat
    let motion: Bool

    @State private var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.25)
            .fill(Color.accentColor)
            .frame(width: 2.5, height: height)
            .opacity(on ? 1 : 0.15)
            .task {
                guard motion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(530))
                    withAnimation(.easeInOut(duration: 0.2)) { on.toggle() }
                }
            }
    }
}
