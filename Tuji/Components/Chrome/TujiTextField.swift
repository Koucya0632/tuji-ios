// Text input — replaces the rounded system field.
//
// No border at rest: the field is told apart from the page by its ground, the
// same way every other region in this system is. A border appears only when the
// field is focused or wrong, which is the rule the whole design follows —
// borders mean focus, selection or warning, never "this is a box".
//
// Focus inverts the grounds (paper2 → paper) and adds the 瞳黃 ring. That is
// deliberate: 瞳黃 means 現在, and a focused field is exactly where the user is.

import SwiftUI

struct TujiTextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var lineLimit: ClosedRange<Int>?
    var errorMessage: String?

    @FocusState private var focused: Bool

    private var isMultiline: Bool {
        self.lineLimit != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Group {
                if let lineLimit = self.lineLimit {
                    TextField(self.placeholder, text: self.$text, axis: .vertical)
                        .lineLimit(lineLimit)
                } else {
                    TextField(self.placeholder, text: self.$text)
                }
            }
            .font(.tujiBody)
            .foregroundStyle(.tujiInk)
            .focused(self.$focused)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, self.isMultiline ? Space.s3 : 0)
            .frame(minHeight: self.isMultiline ? 120 : 52, alignment: self.isMultiline ? .topLeading : .leading)
            .background(self.focused ? Color.tujiPaper : .tujiPaper2)
            .overlay {
                if let border = self.borderColor {
                    Rectangle().stroke(border, lineWidth: Border.bw2)
                }
            }
            .animation(Motion.ease(Motion.d1), value: self.focused)

            if let errorMessage = self.errorMessage {
                Text(verbatim: errorMessage)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiAlert)
            }
        }
    }

    private var borderColor: Color? {
        if self.errorMessage != nil { return .tujiAlert }
        return self.focused ? .tujiEye : nil
    }
}

/// A labelled field for form screens: the label sits above the input as an
/// overline rather than beside it, so the input can run the full page width.
struct TujiField<Content: View>: View {
    let label: LocalizedStringKey
    var footer: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(self.label)
                .font(.tujiLabel)
                .tracking(0.5)
                .foregroundStyle(.tujiInk3)
            self.content
            if let footer = self.footer {
                Text(footer)
                    .font(.tujiBodySm)
                    .foregroundStyle(.tujiInk3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s4)
    }
}

#Preview {
    struct Demo: View {
        @State private var title = ""
        @State private var desc = ""
        var body: some View {
            VStack(spacing: Space.s5) {
                TujiField(label: "標題") {
                    TujiTextField(placeholder: "例如：生活日常", text: self.$title)
                }
                TujiField(label: "簡介（選填）", footer: "公開合集時會一起送審。") {
                    TujiTextField(placeholder: "簡單描述這個合集", text: self.$desc, lineLimit: 2...4)
                }
            }
            .padding(.vertical, Space.s5)
            .background(.tujiPaper)
        }
    }
    return Demo()
}
