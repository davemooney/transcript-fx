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

    /// Per-word delay applied to the tier-2 morph so the changed words in a
    /// commit animate **sequentially left-to-right** instead of all on the same
    /// frame — the eye can follow where the correction is happening instead of
    /// re-reading the whole block (#5141). Word _i_ in the changed run starts
    /// `i * revisionStagger` later. Set to 0 to morph the whole run at once
    /// (the pre-#5141 behavior).
    public var revisionStagger: TimeInterval = 0.045
    /// Ceiling on the total stagger across one commit, so a long paragraph
    /// doesn't take seconds to ripple through. A word's delay is clamped to this;
    /// every word past the implied threshold starts together at the cap.
    public var maxRevisionStagger: TimeInterval = 0.6

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

    /// Delay before the morph for the token at `runIndex` (its 0-based left-to-
    /// right position within a commit's changed run). Word 0 fires immediately;
    /// each subsequent word is offset by `revisionStagger`, clamped to
    /// `maxRevisionStagger` so a big paragraph ripples through in a bounded time
    /// rather than seconds (#5141). A non-positive index or `revisionStagger`
    /// yields no delay.
    public func revisionDelay(forIndex runIndex: Int) -> TimeInterval {
        guard runIndex > 0, revisionStagger > 0 else { return 0 }
        return min(TimeInterval(runIndex) * revisionStagger, max(0, maxRevisionStagger))
    }

    public static let `default` = TranscriptTheme()

    public static func defaultSpeakerStyle(_ speaker: SpeakerID?) -> SpeakerStyle {
        guard let speaker else { return SpeakerStyle() }
        let palette: [Color] = [.cyan, .orange, .mint, .pink, .yellow, .purple]
        let index = abs(speaker.rawValue.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % palette.count
        return SpeakerStyle(label: speaker.rawValue, color: palette[index])
    }
}
