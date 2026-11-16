import Testing
@testable import WhyFi

@Test(arguments: [
    (-30, SignalQuality.excellent), (-55, .excellent), (-56, .good), (-65, .good),
    (-66, .ok), (-70, .ok), (-71, .weak), (-75, .weak), (-76, .poor), (-80, .poor), (-81, .bad),
])
func qualityFromDBm(dBm: Int, expected: SignalQuality) {
    #expect(SignalQuality(dBm: dBm) == expected)
}

@Test func bandsGroupTheWords() {
    #expect(SignalQuality.excellent.band == .good && SignalQuality.good.band == .good)
    #expect(SignalQuality.ok.band == .ok && SignalQuality.weak.band == .ok)
    #expect(SignalQuality.poor.band == .poor && SignalQuality.bad.band == .poor)
    #expect(SignalQuality.ok.label == "OK")
    #expect(SignalBand.goodFloor == -65 && SignalBand.okFloor == -75)
}
