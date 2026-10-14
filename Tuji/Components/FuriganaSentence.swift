// A Japanese sentence with kana set over its kanji, wrapping like running text.
//
// `FuriganaHeadword` draws one word on one line and shrinks it to fit; a
// sentence has to wrap instead. So the sentence is cut into units that may not
// be split — a kanji run with its ruby, or a single bare kana — and laid out by
// `FlowLayout`. Closing punctuation and small kana stay glued to the unit before
// them, so a line never starts with 。 or ょ.
//
// Every unit reserves a ruby row, empty where there is no ruby, so the base
// characters of a line share one baseline.

import SwiftUI

struct FuriganaSentence: View {
    struct Unit: Equatable {
        let text: String
        let ruby: String?
    }

    let segments: [FuriganaSegment]
    var font: Font = .tujiBody(.strong)
    var rubyFont: Font = .tujiLabel

    var body: some View {
        FlowLayout(spacing: 0) {
            ForEach(Array(Self.units(self.segments).enumerated()), id: \.offset) { _, unit in
                // The base sets the width; the ruby is centred over it and may
                // hang over the kana beside it, the way Japanese is typeset.
                // Sized by the ruby instead, a three-kana reading over one
                // kanji would open a gap on either side of it.
                VStack(spacing: 0) {
                    Text(verbatim: " ")
                        .font(self.rubyFont)
                        .hidden()
                    Text(verbatim: unit.text)
                        .font(self.font)
                        .foregroundStyle(.tujiInk)
                        .lineLimit(1)
                        .fixedSize()
                }
                .overlay(alignment: .top) {
                    if let ruby = unit.ruby {
                        Text(verbatim: ruby)
                            .font(self.rubyFont)
                            .foregroundStyle(.tujiInk3)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
        }
        // Unit by unit, VoiceOver would read the kana and the kanji as
        // separate items. One label, the sentence as written.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: self.segments.map(\.text).joined()))
    }

    /// Characters that may not begin a line: they ride on the unit before.
    private static let gluedToPrevious: Set<Character> = Set("、。，．！？!?）」』】〉》…ーぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮ")

    /// The sentence cut where a line may break.
    static func units(_ segments: [FuriganaSegment]) -> [Unit] {
        var units: [Unit] = []
        for segment in segments {
            if let ruby = segment.ruby, !ruby.isEmpty {
                units.append(Unit(text: segment.text, ruby: ruby))
                continue
            }
            for character in segment.text {
                if self.gluedToPrevious.contains(character), let last = units.popLast() {
                    units.append(Unit(text: last.text + String(character), ruby: last.ruby))
                } else {
                    units.append(Unit(text: String(character), ruby: nil))
                }
            }
        }
        return units
    }
}
