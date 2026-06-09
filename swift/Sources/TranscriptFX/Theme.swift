import SwiftUI

/// Visual identity for one speaker. Returned by `TranscriptTheme.speakerStyle`
/// — swap that closure to plug in your app's people model.
public struct SpeakerStyle {
    /// Label shown above the speaker's paragraphs (nil hides the label).
    public var label: String?
    public var color: Color

    public init(label: String? = nil, color: Color = .secondary) {
        self.label = label
        self.color = color
    }
}

/// Everything tunable about how a transcript looks and moves.
public struct TranscriptTheme {
    public var baseFontSize: CGFloat = 22
    public var fontDesign: Font.Design = .default

    // Ink-settle ramp: state + confidence → weight + opacity.
    public var lowConfidenceWeight: Font.Weight = .ultraLight
    public var provisionalWeight: Font.Weight = .light
    public var revisedWeight: Font.Weight = .regular
    public var finalizedWeight: Font.Weight = .semibold
    public var lowConfidenceOpacity: Double = 0.42
    public var provisionalOpacity: Double = 0.6
    public var revisedOpacity: Double = 0.85
    /// Below this confidence a provisional token renders extra-light.
    public var confidenceThreshold: Double = 0.6

    // Motion.
    public var settleDuration: TimeInterval = 0.45
    public var revisionDuration: TimeInterval = 0.35
    public var flashDuration: TimeInterval = 0.9
    public var revisionFlashColor: Color = .indigo
    /// nil follows the system Reduce Motion setting; true/false overrides it.
    public var reduceMotion: Bool? = nil

    // Layout.
    public var wordSpacing: CGFloat = 7
    public var lineSpacing: CGFloat = 10
    public var paragraphSpacing: CGFloat = 22

    // Speakers.
    public var showSpeakerLabels = true
    /// Tint each speaker's words with their color (labels are always tinted).
    public var colorizeSpeakerText = false
    /// Pluggable speaker styling. The default cycles a small palette keyed
    /// deterministically by speaker ID and uses the raw ID as the label.
    public var speakerStyle: (SpeakerID?) -> SpeakerStyle = TranscriptTheme.defaultSpeakerStyle

    public init() {}

    public static let `default` = TranscriptTheme()

    public static func defaultSpeakerStyle(_ speaker: SpeakerID?) -> SpeakerStyle {
        guard let speaker else { return SpeakerStyle() }
        let palette: [Color] = [.cyan, .orange, .mint, .pink, .yellow, .purple]
        let index = abs(speaker.rawValue.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % palette.count
        return SpeakerStyle(label: speaker.rawValue, color: palette[index])
    }
}
