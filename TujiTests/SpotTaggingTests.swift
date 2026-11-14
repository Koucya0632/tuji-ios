// 自製圖鑑掛景點 on the device (parent repo CONTEXT.md「景點」, docs/adr/0002).
//
// THE RED LINES:
//   - The photo's GPS is read from the picked bytes and never sent: only the
//     spot id it matches rides on the confirm.
//   - A spot matches only a card in its destination's language, and only inside
//     its circle — the same rule as tuji-web `spotAt`.
//   - 「不是在這裡拍的」 is offered only for a card shared to a spot.

import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Tuji

@MainActor
struct SpotTaggingTests {
    /// A JPEG carrying `gps` the way a camera writes it: magnitudes plus N/S/E/W refs.
    private func jpeg(gps: [CFString: Any]?) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        var properties: [CFString: Any] = [:]
        if let gps { properties[kCGImagePropertyGPSDictionary] = gps }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    // MARK: - PhotoLocation

    @Test
    func aPhotoTakenIn淺草ReadsBackWhereItWasTaken() throws {
        let data = try self.jpeg(gps: [
            kCGImagePropertyGPSLatitude: 35.7148, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 139.7967, kCGImagePropertyGPSLongitudeRef: "E"
        ])
        let point = try #require(PhotoLocation.read(from: data))
        #expect(abs(point.lat - 35.7148) < 0.0001)
        #expect(abs(point.lng - 139.7967) < 0.0001)
    }

    @Test
    func southAndWestAreNegative() throws {
        let data = try self.jpeg(gps: [
            kCGImagePropertyGPSLatitude: 33.8688, kCGImagePropertyGPSLatitudeRef: "S",
            kCGImagePropertyGPSLongitude: 70.0, kCGImagePropertyGPSLongitudeRef: "W"
        ])
        let point = try #require(PhotoLocation.read(from: data))
        #expect(point.lat < 0 && point.lng < 0)
    }

    @Test
    func aPhotoWithoutGPSOrNotAnImageHasNoPlace() throws {
        #expect(try PhotoLocation.read(from: self.jpeg(gps: nil)) == nil)
        #expect(PhotoLocation.read(from: Data([0x00, 0x01, 0x02])) == nil)
    }

    // MARK: - TravelSpotMatcher

    private static let json = """
    {"destinations":[{"id":"japan","name":"日本","language":"ja","grid":{"columns":14,"rows":16},
      "regions":[{"id":"kanto","name":"關東","tiles":[[9,7]],"nameAt":[11,7],"cityIds":["tokyo"]}],
      "cities":[{"id":"tokyo","name":"東京","regionId":"kanto","aspect":1.4,"shapes":[],"spots":[
        {"id":"asakusa","name":"淺草","native":"浅草","reading":"あさくさ","at":[0.7,0.2],"label":"right",
         "wordIds":["a"],"open":true,"free":false,"geo":{"lat":35.7148,"lng":139.7967,"radiusM":600}},
        {"id":"ueno","name":"上野","native":"上野","reading":"うえの","at":[0.5,0.2],"label":"left",
         "wordIds":["b"],"open":true,"free":false,"geo":{"lat":35.7146,"lng":139.7732,"radiusM":700}},
        {"id":"akihabara","name":"秋葉原","native":"秋葉原","reading":"あきはばら","at":[0.6,0.4],"label":"right",
         "wordIds":["c"],"open":true,"free":true,"geo":{"lat":35.6984,"lng":139.7731,"radiusM":500}},
        {"id":"closed","name":"未開","native":"未開","reading":"みかい","at":[0.1,0.1],"label":"left",
         "wordIds":["d"],"open":false,"free":false}
      ]}]}]}
    """

    private func destinations() throws -> [TravelDestination] {
        try JSONDecoder().decode(TravelResponse.self, from: Data(Self.json.utf8)).destinations
    }

    @Test
    func aPointInsideASpotsCircleMatchesItForAJapaneseCard() throws {
        let japan = try self.destinations()
        #expect(TravelSpotMatcher.match(GeoPoint(lat: 35.7111, lng: 139.7963), in: japan, targetLanguage: "ja")?.id
            == "asakusa")
        // 御徒町, between 上野 and 秋葉原, is neither.
        #expect(TravelSpotMatcher.match(GeoPoint(lat: 35.7075, lng: 139.7745), in: japan, targetLanguage: "ja") == nil)
        // An English card never sits at a Japanese spot.
        #expect(TravelSpotMatcher.match(GeoPoint(lat: 35.7148, lng: 139.7967), in: japan, targetLanguage: "en") == nil)
    }

    @Test
    func anOlderServerWithoutGeoOrLanguageSuggestsNothing() throws {
        let old = Self.json.replacingOccurrences(of: "\"language\":\"ja\",", with: "")
        let japan = try JSONDecoder().decode(TravelResponse.self, from: Data(old.utf8)).destinations
        #expect(japan.first?.language == nil)
        #expect(TravelSpotMatcher.match(GeoPoint(lat: 35.7148, lng: 139.7967), in: japan, targetLanguage: "ja") == nil)
    }

    @Test
    func oneKilometreIsAboutOneKilometre() {
        let d = TravelSpotMatcher.distanceMeters(GeoPoint(lat: 35, lng: 139), GeoPoint(lat: 35.009, lng: 139))
        #expect(d > 990 && d < 1010)
    }

    // MARK: - The card page's rules

    @Test
    func aCardIsOfferedOnlyOpenSpotsInItsLanguage() throws {
        let japan = try self.destinations()
        let ja = AtlasFixtures.item("t1", imageId: "i1", language: .ja)
        #expect(ja.taggableSpots(in: japan).map(\.id) == ["asakusa", "ueno", "akihabara"])
        let en = AtlasFixtures.item("t2", imageId: "i2", language: .en)
        #expect(en.taggableSpots(in: japan).isEmpty)
    }

    @Test
    func sharingNeedsAPublicCardAtASpotItWasNotTakenOff() {
        var item = AtlasFixtures.item("t1", imageId: "i1", reviewStatus: "approved")
        item = item.with(visibility: "public", spotId: "asakusa")
        #expect(item.canShareToSpot)
        #expect(!item.with(visibility: "private", spotId: "asakusa").canShareToSpot)
        #expect(!item.with(visibility: "public", spotId: nil).canShareToSpot)
        #expect(!item.with(visibility: "public", spotId: "asakusa", blocked: true).canShareToSpot)
        let withdrawn = AtlasFixtures.item("t2", imageId: "i2", reviewStatus: "withdrawn")
            .with(visibility: "public", spotId: "asakusa")
        #expect(!withdrawn.canShareToSpot)
        let queued = AtlasFixtures.item("t3", imageId: "i3", reviewStatus: "pending_auto")
            .with(visibility: "public", spotId: "asakusa")
        #expect(queued.canShareToSpot)
    }

    // MARK: - Reports

    @Test
    func 不是在這裡拍的IsOfferedOnlyForACardSharedToASpot() {
        #expect(!AtlasReportReason.choices(atSpot: false).contains(.notHere))
        #expect(AtlasReportReason.choices(atSpot: true).last == .notHere)
        #expect(AtlasReportReason.notHere.rawValue == "not_here")

        let flow = ReportFlow()
        flow.begin(.collection(slug: "c1"))
        #expect(!flow.reasons.contains(.notHere))
        flow.begin(.item(slug: "s1"), atSpot: true)
        #expect(flow.reasons.contains(.notHere))
        flow.begin(.item(slug: "s2"))
        #expect(!flow.reasons.contains(.notHere))
    }

    @Test
    func aPublicCardCarriesItsSpotOnlyWhenTheServerSendsOne() throws {
        let shared = try JSONDecoder().decode(AtlasPublicItem.self, from: Data("""
        {"id":"p1","slug":"s1","lemma":"提灯","displayZhHant":"燈籠","targetLanguage":"ja","category":null,
         "imageUrl":null,"author":null,"publishedAt":null,"spotId":"asakusa"}
        """.utf8))
        #expect(shared.spotId == "asakusa")
        let plain = try JSONDecoder().decode(AtlasPublicItem.self, from: Data("""
        {"id":"p2","slug":"s2","lemma":"提灯","displayZhHant":"燈籠","targetLanguage":"ja","category":null,
         "imageUrl":null,"author":null,"publishedAt":null}
        """.utf8))
        #expect(plain.spotId == nil)
    }

    // MARK: - The journalled confirm

    @Test
    func aConfirmJournalledBeforeSpotsStillDecodesAndANewOneRoundTrips() throws {
        let old = try JSONDecoder().decode(CreditConfirmRequest.self, from: Data("""
        {"operationId":"op-1","candidateId":"c1","lemma":"cat","displayZhHant":"貓"}
        """.utf8))
        #expect(old.spotId == nil)

        var request = old
        request.spotId = "asakusa"
        let encoded = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(CreditConfirmRequest.self, from: encoded) == request)
        // Nothing but the id: no coordinates exist on the request to leak.
        let keys = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any]).keys
        #expect(Set(keys) == ["operationId", "candidateId", "lemma", "displayZhHant", "spotId"])
    }
}

extension AtlasItem {
    /// A copy with the publication and 景點 fields a test is about.
    func with(visibility: String?, spotId: String?, blocked: Bool = false) -> AtlasItem {
        AtlasItem(
            id: self.id, imageId: self.imageId, targetLanguage: self.targetLanguage,
            canonicalWordId: self.canonicalWordId, primaryLabel: self.primaryLabel, fineLabel: self.fineLabel,
            lemma: self.lemma, displayZhHant: self.displayZhHant, displayJa: self.displayJa, displayEn: self.displayEn,
            partOfSpeech: self.partOfSpeech, cefrLevel: self.cefrLevel, pronunciation: self.pronunciation,
            reading: self.reading, category: self.category, taxonomyPath: self.taxonomyPath,
            definitionZhHant: self.definitionZhHant, definitionTarget: self.definitionTarget,
            exampleTarget: self.exampleTarget, exampleZhHant: self.exampleZhHant, noteZhHant: self.noteZhHant,
            visibility: visibility, reviewStatus: self.reviewStatus, publicSlug: self.publicSlug,
            createdAt: self.createdAt, updatedAt: self.updatedAt, deletedAt: self.deletedAt,
            spotId: spotId, spotShared: false, spotShareBlocked: blocked
        )
    }
}

@MainActor
struct SpotMutationTests {
    @Test
    func aSpotChangeMovesNeither圖鑑NorThe物見Feed() {
        #expect(!AtlasMutation.itemSpotChanged.changesOwnAtlas)
        #expect(!AtlasMutation.itemSpotChanged.invalidatesPublicFeed)
    }
}
