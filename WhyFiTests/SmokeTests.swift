import Foundation
import Testing

@Test func appBundleIdentifier() {
    #expect(Bundle.main.bundleIdentifier == "io.github.timfurlong.WhyFi")
}
