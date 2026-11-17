import Foundation
import Testing
@testable import WhyFi

private let t0 = Date(timeIntervalSince1970: 1_794_865_260)

private func r(_ s: Double, _ band: WiFiBand, ch: Int = 149, bssid: String? = "aa") -> SignalReading {
    SignalReading(time: t0 + s, rssi: -60, noise: -95, txRate: 400, channel: ch, band: band, widthMHz: 80, bssid: bssid)
}

@Test func segmentsSplitWhenBandChanges() {
    let segments = LoadedRun.segments([r(0, .ghz5), r(1, .ghz5), r(2, .ghz5), r(3, .ghz2_4), r(4, .ghz2_4)])
    #expect(segments.map(\.count) == [3, 2])
}

@Test func unknownBandNeitherSplitsNorSwitches() {
    let readings = [r(0, .ghz5), r(1, .unknown), r(2, .ghz5)]
    #expect(LoadedRun.segments(readings).count == 1)
    #expect(LoadedRun.switches(readings) == [])
}

@Test func switchesFindBandAndAccessPointChanges() {
    let readings = [r(0, .ghz5, bssid: "aa"), r(1, .ghz2_4, ch: 6, bssid: "bb"), r(2, .ghz2_4, ch: 6, bssid: "cc")]
    #expect(LoadedRun.switches(readings) == [
        LinkSwitch(time: t0 + 1, band: .ghz2_4, bandChanged: true),
        LinkSwitch(time: t0 + 2, band: .ghz2_4, bandChanged: false),
    ])
}

@Test func switchesWithoutBSSIDsStillFindBandChanges() {
    let readings = [r(0, .ghz5, bssid: nil), r(1, .ghz5, bssid: nil), r(2, .ghz2_4, bssid: nil)]
    #expect(LoadedRun.switches(readings) == [LinkSwitch(time: t0 + 2, band: .ghz2_4, bandChanged: true)])
}

@Test func switchAcrossAGapCounts() {
    let readings = [r(0, .ghz5), r(1, .ghz5), r(10, .ghz2_4), r(11, .ghz2_4)]
    #expect(LoadedRun.switches(readings) == [LinkSwitch(time: t0 + 10, band: .ghz2_4, bandChanged: true)])
}

@Test func bandSummaryPicksTheMostUsedBand() {
    let readings = [r(0, .ghz5), r(1, .ghz5)] + (2...5).map { r(Double($0), .ghz2_4, ch: 6) }
    #expect(LoadedRun.bandSummary(readings) == BandSummary(band: .ghz2_4, channel: 6, switchCount: 1))
}

@Test func bandSummaryIsNilWithoutReadings() {
    #expect(LoadedRun.bandSummary([]) == nil)
    #expect(LoadedRun.bandSummary([r(0, .unknown), r(1, .unknown)]) == nil)
}

@Test func labelsSkipSwitchesTooCloseTogether() {
    let switches = [0.0, 5, 20, 30].map { LinkSwitch(time: t0 + $0, band: .ghz2_4, bandChanged: true) }
    #expect(LinkSwitch.labeled(switches) == [true, false, true, false])
}

@Test func labelGapScalesWithTheChartsSpan() {
    #expect(LinkSwitch.labelGap(forSpan: 60) == 15)
    #expect(LinkSwitch.labelGap(forSpan: 600) == 75)
}

@Test func accessPointLabelsGiveWayToBandLabels() {
    let switches = [LinkSwitch(time: t0, band: .ghz5, bandChanged: false),
                    LinkSwitch(time: t0 + 10, band: .ghz2_4, bandChanged: true)]
    #expect(LinkSwitch.labeled(switches, minGap: 15) == [false, true])
}

@Test func accessPointLabelsFarFromBandLabelsStay() {
    let switches = [LinkSwitch(time: t0, band: .ghz5, bandChanged: false),
                    LinkSwitch(time: t0 + 30, band: .ghz2_4, bandChanged: true)]
    #expect(LinkSwitch.labeled(switches, minGap: 15) == [true, true])
}

@Test func accessPointSwitchesAreDrawnInOpaqueGray() {
    #expect(RunChart.color(of: LinkSwitch(time: t0, band: .ghz5, bandChanged: false)) == Palette.band(.unknown))
    #expect(RunChart.color(of: LinkSwitch(time: t0, band: .ghz2_4, bandChanged: true)) == Palette.band(.ghz2_4))
}
