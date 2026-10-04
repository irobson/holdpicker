import Testing
import Foundation
@testable import TedCatCore

@Suite("VideoEncodingPlan")
struct VideoEncodingPlanTests {
    @Test("Output keeps native pixel density and even dimensions")
    func retinaEvenDimensions() throws {
        let plan = try #require(VideoEncodingPlan(pointSize: CGSize(width: 401.3, height: 300.7), scale: 2))
        #expect(plan.pixelWidth == 802)
        #expect(plan.pixelHeight == 600)
        #expect(plan.pixelWidth % 2 == 0 && plan.pixelHeight % 2 == 0)
    }

    @Test("Odd pixel sizes round down to even")
    func oddRoundsDown() throws {
        let plan = try #require(VideoEncodingPlan(pointSize: CGSize(width: 101, height: 77), scale: 1))
        #expect(plan.pixelWidth == 100)
        #expect(plan.pixelHeight == 76)
    }

    @Test("Bitrate scales with area and stays within bounds")
    func bitrateBounds() throws {
        let tiny = try #require(VideoEncodingPlan(pointSize: CGSize(width: 40, height: 40), scale: 1))
        #expect(tiny.averageBitrate == VideoEncodingPlan.minimumBitrate)

        let huge = try #require(VideoEncodingPlan(pointSize: CGSize(width: 3000, height: 2000), scale: 2))
        #expect(huge.averageBitrate == VideoEncodingPlan.maximumBitrate)

        let mid = try #require(VideoEncodingPlan(pointSize: CGSize(width: 800, height: 600), scale: 2))
        #expect(mid.averageBitrate > VideoEncodingPlan.minimumBitrate)
        #expect(mid.averageBitrate < VideoEncodingPlan.maximumBitrate)
    }

    @Test("Regions too small to encode are rejected")
    func tooSmall() {
        #expect(VideoEncodingPlan(pointSize: CGSize(width: 10, height: 200), scale: 2) == nil)
    }
}
