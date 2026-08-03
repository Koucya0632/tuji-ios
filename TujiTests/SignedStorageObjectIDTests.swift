// Pins the cache identity the image pipeline hands Nuke for private-bucket
// (自製圖鑑) images. Supabase re-signs on every API response, so keying on the
// full URL re-downloads every thumbnail on every visit to 圖鑑管理.
//
// The host in these fixtures is deliberately arbitrary: the rule keys on the
// storage path, not on who is serving it.

import Foundation
import Nuke
import Testing
import UIKit
@testable import Tuji

struct SignedStorageObjectIDTests {
    private let original = "https://files.example.com/storage/v1/object/sign/user-atlas-images/u/i/original.webp"
    private let thumb = "https://files.example.com/storage/v1/object/sign/user-atlas-images/u/i/thumb.webp"

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    @Test
    func twoSignaturesOfOneObjectShareAnIdentity() throws {
        let first = try self.url("\(self.original)?token=eyJhbGciOi.FIRST.signature")
        let second = try self.url("\(self.original)?token=eyJhbGciOi.SECOND.signature")

        #expect(first.signedStorageObjectID != nil)
        #expect(first.signedStorageObjectID == second.signedStorageObjectID)
        #expect(first.absoluteString != second.absoluteString)
    }

    @Test
    func differentObjectsKeepDifferentIdentities() throws {
        let thumb = try self.url("\(self.thumb)?token=a")
        let original = try self.url("\(self.original)?token=a")

        #expect(thumb.signedStorageObjectID != original.signedStorageObjectID)
    }

    /// A transform parameter says which picture you get back, so it is part of
    /// the identity — only the rotating signature is dropped.
    @Test
    func nonSignatureQueryItemsSurvive() throws {
        let small = try self.url("\(self.original)?width=100&token=a")
        let large = try self.url("\(self.original)?width=800&token=b")

        #expect(small.signedStorageObjectID != large.signedStorageObjectID)
        #expect(small.signedStorageObjectID?.contains("width=100") == true)
        #expect(small.signedStorageObjectID?.contains("token") == false)
    }

    /// Public images already have stable URLs; nil hands them back to Nuke's
    /// default key rather than inventing one.
    @Test
    func unsignedURLsFallThroughToTheDefaultKey() throws {
        let publicObject = try self.url(
            "https://files.example.com/storage/v1/object/public/word-images/cat.webp"
        )

        #expect(publicObject.signedStorageObjectID == nil)
        #expect(try self.url("https://cdn.example.com/cover.png").signedStorageObjectID == nil)
    }

    /// The one that matters: the key is actually wired into the pipeline the
    /// app installs, so a thumbnail fetched under last visit's signature is
    /// still a cache hit under this visit's.
    @Test
    func theInstalledPipelineHitsCacheAcrossSignatures() throws {
        let pipeline = TujiImagePipeline.makePipeline(dataCache: nil)
        let cached = ImageContainer(image: UIImage())

        try pipeline.cache[ImageRequest(url: self.url("\(self.original)?token=first"))] = cached

        let nextVisit = try ImageRequest(url: self.url("\(self.original)?token=second"))
        let otherImage = try ImageRequest(url: self.url("\(self.thumb)?token=second"))

        #expect(pipeline.cache[nextVisit] != nil)
        #expect(pipeline.cache[otherImage] == nil)
    }
}
