// Font tokens — Plus Jakarta Sans (Latin) + Noto Sans TC (CJK fallback).
// Font.custom returns a usable system fallback if the .ttf isn't installed,
// so this compiles & renders fine before the font files are bundled.
// no_font_custom_outside_theme lint rule keeps Font.custom restricted here.

import SwiftUI

extension Font {
    static let tujiDisplay = Font.custom("PlusJakartaSans-ExtraBold", size: 60)
    static let tujiH1 = Font.custom("PlusJakartaSans-Bold", size: 44)
    static let tujiH2 = Font.custom("PlusJakartaSans-Bold", size: 28)
    static let tujiH3 = Font.custom("PlusJakartaSans-Bold", size: 22)
    static let tujiH4 = Font.custom("PlusJakartaSans-SemiBold", size: 18)
    static let tujiBodyLg = Font.custom("PlusJakartaSans-Regular", size: 16)
    static let tujiBody = Font.custom("PlusJakartaSans-Regular", size: 14)
    static let tujiCaption = Font.custom("PlusJakartaSans-Regular", size: 12)
    static let tujiOverline = Font.custom("PlusJakartaSans-SemiBold", size: 12)
    static let tujiMono = Font.custom("JetBrainsMono-Regular", size: 13)
}
