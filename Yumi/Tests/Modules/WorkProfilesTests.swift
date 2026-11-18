import Testing
import Foundation

// The first launch asks what the person mostly does; the modules follow it.

@Suite struct WorkProfilesTests {
    private let available = ["claude-code", "github", "gmail", "agenda", "notes", "weather", "music", "focus", "notion", "screen-time"]
    private func profiles(_ ids: String...) -> [WorkProfile] { ids.compactMap(WorkProfiles.profile) }

    @Test func aBakerGetsNoCodingModules() {
        let modules = WorkProfiles.modules(for: profiles("shop"), available: available, limit: 10)
        #expect(Array(modules.prefix(5)) == ["gmail", "agenda", "notes", "weather", "music"])
        #expect(!modules.contains("claude-code") && !modules.contains("github"))
    }

    @Test func someoneWhoCodesGetsTheAgentsFirst() {
        let modules = WorkProfiles.modules(for: profiles("code"), available: available, limit: 10)
        #expect(Array(modules.prefix(5)) == ["claude-code", "github", "focus", "music", "agenda"])
    }

    @Test func severalProfilesTakeTheFirstOfEachThenTheNext() {
        // Work before personal life, whatever the order they were ticked in.
        let modules = WorkProfiles.modules(for: profiles("personal", "code"), available: available, limit: 10)
        #expect(Array(modules.prefix(4)) == ["claude-code", "agenda", "github", "notes"])
        #expect(Set(modules).count == modules.count)
        #expect(modules.count <= 10)
        #expect(WorkProfiles.modules(for: profiles("code"), available: available, limit: 5).count == 5)
    }

    @Test func onlyModulesOfThisBuild() {
        let modules = WorkProfiles.modules(for: profiles("freelance"), available: ["agenda", "notes"], limit: 10)
        #expect(modules == ["agenda", "notes"])
        #expect(WorkProfiles.modules(for: [], available: available, limit: 10).isEmpty)
    }

    @Test func aFreeWordFindsItsProfile() {
        #expect(WorkProfiles.match("boulangère")?.id == "shop")
        #expect(WorkProfiles.match("Je suis infirmière de nuit")?.id == "field")
        #expect(WorkProfiles.match("facteur")?.id == "field")
        #expect(WorkProfiles.match("prof de maths")?.id == "teach")
        #expect(WorkProfiles.match("chef de projet")?.id == "office")
        #expect(WorkProfiles.match("youtubeuse")?.id == "video")
        #expect(WorkProfiles.match("développeur iOS")?.id == "code")
        #expect(WorkProfiles.match("étudiante en droit")?.id == "study")
        #expect(WorkProfiles.match("astronaute") == nil)
        #expect(WorkProfiles.match("") == nil)
    }

    @Test func everyProfileHasItsWordsAndModules() {
        #expect(WorkProfiles.all.count == 12)
        #expect(Set(WorkProfiles.all.map(\.id)).count == 12)
        for profile in WorkProfiles.all {
            #expect(profile.modules.count >= 5, "\(profile.id)")
            #expect(profile.modules.allSatisfy(available.contains), "\(profile.id)")
            #expect(!profile.label.isEmpty && profile.memory.hasSuffix("."), "\(profile.id)")
        }
        #expect(WorkProfiles.detected(codingAgentInstalled: true) == ["code"])
        #expect(WorkProfiles.detected(codingAgentInstalled: false).isEmpty)
        #expect(WorkProfiles.memory(ofFreeAnswer: "  boulangère  ") == "Ton activité : boulangère.")
        #expect(WorkProfiles.memory(ofFreeAnswer: " ") == nil)
    }
}
