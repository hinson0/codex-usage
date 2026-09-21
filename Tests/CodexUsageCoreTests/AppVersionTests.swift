import Testing
@testable import CodexUsageCore

@Suite
struct AppVersionTests {
    @Test
    func formatsSemanticVersionFromBundleMetadata() {
        #expect(AppVersion.displayString(infoDictionary: [
            "CFBundleShortVersionString": "0.2.0",
        ]) == "v0.2.0")
    }

    @Test
    func missingOrBlankVersionStaysHidden() {
        #expect(AppVersion.displayString(infoDictionary: [:]) == nil)
        #expect(AppVersion.displayString(infoDictionary: [
            "CFBundleShortVersionString": "   ",
        ]) == nil)
    }
}
