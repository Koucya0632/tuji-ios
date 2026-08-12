// Pins the shared 取像 flow's state machine: the encode profile that used to
// differ silently between 合集 and 個人資料, the single error line that replaced
// two competing channels, and the retry latch only one of the screens had.
//
// The module was `AvatarPicker` and covered two of its three callers; 拍照新增
// hand-wrote the same seven steps and was covered by none of this.

import Foundation
import Testing
import UIKit
@testable import Tuji

@MainActor
struct ImageIntakeTests {
    /// A real (tiny) JPEG, so the encode step runs for real rather than against
    /// a stub — a decode failure here would be indistinguishable from a
    /// delivery failure otherwise.
    private func sampleImageData() throws -> Data {
        let size = CGSize(width: 8, height: 8)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return try #require(image.jpegData(compressionQuality: 1))
    }

    @Test
    func theThreeScreensDifferOnlyInTheEncodeProfile() {
        #expect(ImageIntakeEncoding.profile == ImageIntakeEncoding(maxPixelSize: 1200, quality: 0.86))
        #expect(ImageIntakeEncoding.collection == ImageIntakeEncoding(maxPixelSize: 1600, quality: 0.82))
        // 拍照新增: the backend caps stored images at 1600 and recognition only
        // sees 1024, so this is the profile the upload pipeline is tuned for.
        #expect(ImageIntakeEncoding.capture == ImageIntakeEncoding(maxPixelSize: 1600, quality: 0.78))
        #expect(ImageIntakeEncoding.profile != ImageIntakeEncoding.collection)
        #expect(ImageIntakeEncoding.collection != ImageIntakeEncoding.capture)
    }

    @Test
    func aRejectionCanCarryTheScreensOwnReason() async throws {
        // 拍照新增 delivers by uploading, and the server's description of why an
        // upload failed beats the module's generic line.
        let intake = ImageIntake(encoding: .capture, crop: .freeform) { _ in
            .rejected("連線逾時")
        }

        try await intake.handleCropped(self.sampleImageData())

        #expect(intake.errorMessage == "連線逾時")
        #expect(intake.canRetry)
    }

    @Test
    func aScreenWithItsOwnButtonsSkipsTheChooser() {
        // 拍照新增's source panel carries the remaining-allowance line and the
        // capacity warning, so it opens a source directly.
        let intake = ImageIntake(encoding: .capture, crop: .freeform)

        intake.pick(.camera)
        #expect(intake.showCamera)
        #expect(!intake.showSources)

        let library = ImageIntake(encoding: .capture, crop: .freeform)
        library.pick(.photoLibrary)
        #expect(library.showPhotoLibrary)
        #expect(!library.showSources)
    }

    @Test
    func aCroppedPhotoIsEncodedAndDelivered() async throws {
        var delivered: Data?
        let picker = ImageIntake(encoding: .collection, crop: .square(mask: .square)) { data in
            delivered = data
            return .accepted
        }

        try await picker.handleCropped(self.sampleImageData())

        #expect(delivered != nil)
        #expect(picker.phase == .idle)
        #expect(picker.errorMessage == nil)
        #expect(!picker.canRetry)
        #expect(!picker.isBusy)
    }

    /// One error line for the whole flow. 合集 used to render its VM's shared
    /// `errorMessage` here — defined as "a failed publish wins" — so a stale
    /// meta-save failure showed up as an avatar upload failure.
    @Test
    func aFailedDeliveryParksTheBytesForRetry() async throws {
        var attempts = 0
        let picker = ImageIntake(encoding: .profile) { _ in
            attempts += 1
            return .rejected(nil)
        }

        try await picker.handleCropped(self.sampleImageData())

        #expect(attempts == 1)
        #expect(picker.errorMessage != nil)
        #expect(picker.canRetry)
    }

    @Test
    func retryResendsTheSameBytesAndClearsTheErrorOnSuccess() async throws {
        var attempts = 0
        var seen: [Int] = []
        let picker = ImageIntake(encoding: .profile) { data in
            attempts += 1
            seen.append(data.count)
            return attempts > 1 ? .accepted : .rejected(nil)
        }

        try await picker.handleCropped(self.sampleImageData())
        #expect(picker.canRetry)

        await picker.retry()

        #expect(attempts == 2)
        // The retry re-sends the encoded photo rather than making the user pick
        // it again, so both attempts carry identical bytes.
        #expect(seen.count == 2)
        #expect(seen[0] == seen[1])
        #expect(picker.phase == .idle)
        #expect(picker.errorMessage == nil)
        #expect(!picker.canRetry)
    }

    @Test
    func retryDoesNothingWithoutAParkedPhoto() async {
        var attempts = 0
        let picker = ImageIntake(encoding: .profile) { _ in
            attempts += 1
            return .accepted
        }

        await picker.retry()

        #expect(attempts == 0)
        #expect(!picker.canRetry)
    }

    @Test
    func anUnreadablePhotoFailsBeforeItIsEverDelivered() async {
        var attempts = 0
        let picker = ImageIntake(encoding: .profile) { _ in
            attempts += 1
            return .accepted
        }

        await picker.handleCropped(Data("not an image".utf8))

        #expect(attempts == 0)
        #expect(picker.errorMessage != nil)
        // Nothing was encoded, so there is nothing to retry.
        #expect(!picker.canRetry)
    }

    @Test
    func beginOpensTheSourceChooserAndClearsAStaleError() async throws {
        let picker = ImageIntake(encoding: .profile) { _ in .rejected(nil) }
        try await picker.handleCropped(self.sampleImageData())
        #expect(picker.errorMessage != nil)

        picker.begin()

        #expect(picker.showSources)
        #expect(picker.errorMessage == nil)
    }

    @Test
    func deliveryCanBeConnectedAfterConstruction() async throws {
        // SwiftUI gives a @State initializer no access to @Environment, so the
        // screens wire their upload from `.task`.
        let picker = ImageIntake(encoding: .collection, crop: .square(mask: .square))
        var delivered = false
        picker.onDeliver { _ in
            delivered = true
            return .accepted
        }

        try await picker.handleCropped(self.sampleImageData())

        #expect(delivered)
        #expect(picker.phase == .idle)
    }
}
