import Observation
import Nuke
import NukeUI
import SwiftUI

/// One shared projection for collection identity. A freshly accepted upload
/// overlays both photo and fallback color everywhere already on screen.
@MainActor
@Observable
final class CollectionIdentityStore {
    private static let fallbackPalette = [
        "#557a95", "#6f6aa8", "#9b626a", "#a06d3f",
        "#4f8175", "#7d6952", "#6b789f", "#8c5f86",
        "#547f9f", "#8f7047", "#567d63", "#78689a"
    ]

    private var acceptedColors: [String: String] = [:]
    private var acceptedImageURLs: [String: URL] = [:]
    private(set) var revision = 0

    func publish(collectionID: String, avatarColor: String, avatarImageURL: URL? = nil) {
        var changed = false
        if let color = Self.acceptedHex(avatarColor) {
            self.acceptedColors[collectionID] = color
            changed = true
        }
        if let avatarImageURL {
            self.acceptedImageURLs[collectionID] = avatarImageURL
            changed = true
        }
        if changed { self.revision += 1 }
    }

    func colorHex(collectionID: String, serverColor: String?) -> String {
        if let accepted = self.acceptedColors[collectionID] { return accepted }
        if let serverColor, let accepted = Self.acceptedHex(serverColor) { return accepted }
        return Self.fallbackPalette[Self.stableIndex(collectionID)]
    }

    func imageURL(collectionID: String, serverURL: URL?) -> URL? {
        self.acceptedImageURLs[collectionID] ?? serverURL
    }

    private static func acceptedHex(_ raw: String) -> String? {
        let color = raw.lowercased()
        guard color.count == 7, color.first == "#",
              let value = UInt32(color.dropFirst(), radix: 16)
        else { return nil }
        let red = Int((value >> 16) & 0xFF)
        let green = Int((value >> 8) & 0xFF)
        let blue = Int(value & 0xFF)
        let luminance = (299 * red + 587 * green + 114 * blue) / 1000
        guard luminance > 18, luminance < 237 else { return nil }
        return color
    }

    private static func stableIndex(_ id: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % UInt64(Self.fallbackPalette.count))
    }
}

/// The collection avatar. Its extracted color is only a loading/legacy fallback;
/// the collection cover remains a separate compatibility field and is never
/// rendered here.
struct CollectionIdentityTile: View {
    @Environment(CollectionIdentityStore.self) private var identities

    let collectionID: String
    let avatarColor: String?
    let avatarImageURL: URL?
    /// `nil` fills whatever space it is given — the cover case, where the tile
    /// is the screen's first event rather than a thumbnail beside a title.
    var size: CGFloat?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(collectionIdentityHex: self.identities.colorHex(
                    collectionID: self.collectionID,
                    serverColor: self.avatarColor
                )))
            LazyImage(url: self.identities.imageURL(
                collectionID: self.collectionID,
                serverURL: self.avatarImageURL
            )) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                }
            }
            .pipeline(.shared)
        }
        .frame(width: self.size, height: self.size)
        .clipped()
        .accessibilityHidden(true)
    }
}

private extension Color {
    init(collectionIdentityHex hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0x5F7F9F
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
