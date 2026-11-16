import Testing
@testable import WhyFi

@Test func volatileIsReplacedByOverlappingVolatile() {
    var acc = TranscriptAccumulator()
    _ = acc.receive(text: "stand", isFinal: false, start: 0, end: 1)
    _ = acc.receive(text: "standing next", isFinal: false, start: 0, end: 2)
    #expect(acc.volatileText == "standing next")
}

@Test func finalIsReturnedOnce() {
    var acc = TranscriptAccumulator()
    let first = acc.receive(text: " Standing next to the dryer.", isFinal: true, start: 0, end: 2.5)
    #expect(first == [TranscriptSegment(start: 0, end: 2.5, text: "Standing next to the dryer.")])
    #expect(acc.receive(text: "turning", isFinal: false, start: 3, end: 4) == [])
}

@Test func volatileTextExcludesFinals() {
    var acc = TranscriptAccumulator()
    _ = acc.receive(text: "standing", isFinal: false, start: 0, end: 2)
    _ = acc.receive(text: "Standing next to the dryer.", isFinal: true, start: 0, end: 2.5)
    #expect(acc.volatileText == "")
    _ = acc.receive(text: "turning", isFinal: false, start: 3, end: 4)
    #expect(acc.volatileText == "turning")
}

@Test func separateVolatilesJoinInTimeOrder() {
    var acc = TranscriptAccumulator()
    _ = acc.receive(text: "the laptop", isFinal: false, start: 2, end: 3)
    _ = acc.receive(text: "turning", isFinal: false, start: 0, end: 1)
    #expect(acc.volatileText == "turning the laptop")
}

@Test func emptyTextIgnored() {
    var acc = TranscriptAccumulator()
    _ = acc.receive(text: "  ", isFinal: false, start: 0, end: 1)
    #expect(acc.volatileText == "")
    #expect(acc.receive(text: "", isFinal: true, start: 0, end: 1) == [])
}
