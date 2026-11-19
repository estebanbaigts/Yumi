import Testing
import Foundation

@Suite struct IslandLookTests {

    private func makeDefaults() -> UserDefaults {
        let name = "yumi.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: Width

    @Test func theWorkTabIsWiderThanTheRelaxTab() {
        #expect(IslandOpenWidth.tab(.work).width(notch: 0) > IslandOpenWidth.tab(.day).width(notch: 0))
        #expect(IslandOpenWidth.tab(.day).width(notch: 0) > IslandOpenWidth.tab(.relax).width(notch: 0))
    }

    @Test func withoutANotchEachViewTakesTheWidthItAsks() {
        for kind: IslandOpenWidth in [.tab(.work), .tab(.day), .tab(.relax), .chat, .alert, .settings] {
            #expect(kind.width(notch: 0) == kind.preferred)
        }
    }

    @Test func aWideNotchLeavesRoomForTheTabsAndTheButtons() {
        let notch: CGFloat = 200
        for kind: IslandOpenWidth in [.tab(.work), .tab(.relax), .chat] {
            #expect(kind.width(notch: notch) >= notch + 2 * IslandOpenWidth.side)
        }
        // The widest tab is not stretched by a notch it already clears
        #expect(IslandOpenWidth.tab(.work).width(notch: 130) == IslandOpenWidth.tab(.work).preferred)
    }

    // MARK: Colour

    @Test func theColourIsYumisOwnUntilChosen() {
        let defaults = makeDefaults()
        #expect(IslandAccent.current(in: defaults) == .yumi)
        #expect(IslandAccent.yumi.restStops == [0x5B8CFF, 0x8B6CFF, 0xF58AD9])
    }

    @Test func aChosenColourIsKept() {
        let defaults = makeDefaults()
        IslandAccent.green.save(in: defaults)
        #expect(IslandAccent.current(in: defaults) == .green)
        defaults.set("not-a-colour", forKey: IslandAccent.defaultsKey)
        #expect(IslandAccent.current(in: defaults) == .yumi)
    }

    @Test func anotherColourTintsTheRimAtRestFromItself() {
        let stops = IslandAccent.orange.restStops
        #expect(stops.count == 3)
        #expect(stops[0] == IslandAccent.orange.hex)
        #expect(IslandAccent.mix(0x000000, 0xFFFFFF, 0.5) == 0x808080)
        #expect(IslandAccent.allCases.count == 7)
    }

    // MARK: Costume

    @Test func noCostumeUntilChosen() {
        #expect(YumiCostume.current(in: makeDefaults()) == YumiCostume.none)
    }

    @Test func aChosenCostumeIsKept() {
        let defaults = makeDefaults()
        YumiCostume.witch.save(in: defaults)
        #expect(YumiCostume.current(in: defaults) == .witch)
        YumiCostume.none.save(in: defaults)
        #expect(YumiCostume.current(in: defaults) == YumiCostume.none)
    }

    @Test func eachCostumeIsWornOnTheHeadOrOnTheFace() {
        for costume in YumiCostume.allCases where costume != .none {
            #expect(costume.onHead || costume.onFace)
        }
        #expect(YumiCostume.cat.onHead && YumiCostume.cat.onFace)
        #expect(YumiCostume.glasses.onFace && !YumiCostume.glasses.onHead)
        #expect(YumiCostume.allCases.count == 14)
        #expect(YumiCostume.pirate.onHead && YumiCostume.pirate.onFace)
    }
}
