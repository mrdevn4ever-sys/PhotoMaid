import Foundation
import Testing
@testable import PhotoMaidCore

@Suite struct SizeEstimateTests {
    @Test func fallbackRatesGivePlausibleIPhoneSizes() {
        let e = SizeEstimator()
        // 12-MP-Foto ≈ 2,4 MB, Live Photo ≈ 4,8 MB, 1 min 1080p-Video ≈ 50 MB – Richtwerte, nur „ca.“.
        #expect(e.estimate(EstimateInput(kind: .photo, pixels: 12_000_000)) == 2_400_000)
        #expect(e.estimate(EstimateInput(kind: .livePhoto, pixels: 12_000_000)) == 4_800_000)
        #expect(e.estimate(EstimateInput(kind: .video, pixels: 1920 * 1080, duration: 60)) == 49_766_400)
        #expect(!e.isCalibrated(.photo))
    }

    @Test func calibratesFromOwnMeasurementsWithMedian() {
        var samples: [SizeSample] = []
        // Fotos dieser Mediathek: 0,3 B/px; ein Ausreißer (RAW) verschiebt den Median nicht.
        for _ in 0..<6 { samples.append(SizeSample(EstimateInput(kind: .photo, pixels: 10_000_000), bytes: 3_000_000)) }
        samples.append(SizeSample(EstimateInput(kind: .photo, pixels: 10_000_000), bytes: 50_000_000))
        // Videos: 0,5 B/(px·s)
        for _ in 0..<5 { samples.append(SizeSample(EstimateInput(kind: .video, pixels: 1_000_000, duration: 10), bytes: 5_000_000)) }
        let e = SizeEstimator(samples: samples)
        #expect(e.isCalibrated(.photo) && e.isCalibrated(.video))
        #expect(e.estimate(EstimateInput(kind: .photo, pixels: 20_000_000)) == 6_000_000)
        #expect(e.estimate(EstimateInput(kind: .video, pixels: 2_000_000, duration: 30)) == 30_000_000)
        // Zu wenige Live Photos gemessen: Richtwert.
        #expect(!e.isCalibrated(.livePhoto))
    }

    @Test func alwaysPositiveEvenWithoutMetadata() {
        let e = SizeEstimator()
        #expect(e.estimate(EstimateInput(kind: .photo)) > 0)
        #expect(e.estimate(EstimateInput(kind: .video, duration: .nan)) > 0)
        #expect(e.estimate(EstimateInput(kind: .file)) == SizeEstimator.fallbackFileBytes)
    }

    @Test func filesUseMedianOfSameType() {
        var samples: [SizeSample] = []
        for b in [1, 2, 3, 4, 5] as [Int64] { samples.append(SizeSample(EstimateInput(kind: .file, fileType: "pdf"), bytes: b * 1000)) }
        for _ in 0..<5 { samples.append(SizeSample(EstimateInput(kind: .file, fileType: "zip"), bytes: 9_000_000)) }
        let e = SizeEstimator(samples: samples)
        #expect(e.estimate(EstimateInput(kind: .file, fileType: "pdf")) == 3000)
        #expect(e.estimate(EstimateInput(kind: .file, fileType: "mov")) == e.fileMedian)
    }

    @Test func roundingToTwoSignificantDigits() {
        #expect(SizeEstimator.rounded(4_876_543) == 4_900_000)
        #expect(SizeEstimator.rounded(123_456_789) == 120_000_000)
        #expect(SizeEstimator.rounded(99) == 99)
        #expect(SizeEstimator.rounded(150) == 150)
    }

    @Test func sumIsApproximateAsSoonAsOnePartIsEstimated() {
        var s = SizeSum([.exact(1_000), .exact(2_000)])
        #expect(s.value == .exact(3_000))
        s.add(.approximate(500))
        #expect(s.value == .approximate(3_500) && s.count == 3)
        #expect(SizeValue.of(.known(7), estimate: 99) == .exact(7))
        #expect(SizeValue.of(.unknown, estimate: 99) == .approximate(99))
    }

    @Test func savingsShowEstimateOnlyWhenEveryUnknownHasOne() {
        let a = ItemReference.photo("a"), b = ItemReference.photo("b"), c = ItemReference.photo("c")
        let s = CleanupSavings.of(removed: [a, b], sizes: [a: .known(1_000)], estimates: [b: 4_000])
        #expect(s.display == .approximate(5_000))
        #expect(s.isLowerBound) // gemessen bleibt „mind.“-Wissen erhalten
        let partial = CleanupSavings.of(removed: [a, b, c], sizes: [a: .known(1_000)], estimates: [b: 4_000])
        #expect(partial.display == .exact(1_000) && partial.estimatedBytes == 0)
        let total = SavingsTotal().adding(s)
        #expect(total.bytes == 5_000 && total.approximate && !total.lowerBound)
        let old = SavingsTotal().adding(CleanupSavings.of(removed: [a, c], sizes: [a: .known(1_000)]))
        #expect(old.bytes == 1_000 && old.lowerBound && !old.approximate)
    }
}
