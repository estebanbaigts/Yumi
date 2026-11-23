import Testing

@Suite struct HoldToTalkTests {
    @Test func holdThenRelease() {
        var hold = HoldToTalk()
        #expect(hold.modifiers(keyCode: 61, rightOptionDown: true, others: false, at: 0) == .nothing)
        #expect(hold.tick(at: 0.1) == .nothing)
        #expect(hold.tick(at: 0.35) == .listen)
        #expect(hold.tick(at: 0.5) == .nothing)
        #expect(hold.modifiers(keyCode: 61, rightOptionDown: false, others: false, at: 2) == .answer)
    }

    @Test func aTapDoesNothing() {
        var hold = HoldToTalk()
        _ = hold.modifiers(keyCode: 61, rightOptionDown: true, others: false, at: 0)
        #expect(hold.modifiers(keyCode: 61, rightOptionDown: false, others: false, at: 0.1) == .nothing)
        #expect(hold.tick(at: 0.5) == .nothing)
    }

    @Test func optionUsedToTypeCancels() {
        var hold = HoldToTalk()
        _ = hold.modifiers(keyCode: 61, rightOptionDown: true, others: false, at: 0)
        _ = hold.tick(at: 0.4)
        #expect(hold.keyTyped() == .cancel)
        #expect(hold.modifiers(keyCode: 61, rightOptionDown: false, others: false, at: 1) == .nothing)
    }

    @Test func anotherModifierCancels() {
        var hold = HoldToTalk()
        _ = hold.modifiers(keyCode: 61, rightOptionDown: true, others: false, at: 0)
        _ = hold.tick(at: 0.4)
        #expect(hold.modifiers(keyCode: 56, rightOptionDown: true, others: true, at: 0.5) == .cancel)
    }

    @Test func theLeftOptionIsIgnored() {
        var hold = HoldToTalk()
        #expect(hold.modifiers(keyCode: 58, rightOptionDown: false, others: false, at: 0) == .nothing)
        #expect(hold.tick(at: 1) == .nothing)
    }
}
