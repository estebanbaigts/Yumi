import Foundation
import Testing

@Suite struct AgentPlaceTests {
    @Test func readsTheBranchFromHead() {
        #expect(AgentPlace.branch(fromHead: "ref: refs/heads/claude/refonte-ile\n") == "claude/refonte-ile")
        #expect(AgentPlace.branch(fromHead: "55a954d0123456789\n") == "55a954d")
    }

    @Test func namesTheModels() {
        #expect(AgentPlace.modelName("claude-opus-4-5-20251101") == "Opus 4.5")
        #expect(AgentPlace.modelName("claude-sonnet-4-5") == "Sonnet 4.5")
        #expect(AgentPlace.modelName("gpt-5-codex") == "gpt-5-codex")
    }

    @Test func findsTheLastModelOfATranscript() {
        let text = #"{"message":{"model":"claude-sonnet-4-5"}}"# + "\n" + #"{"message":{"model":"claude-opus-4-5-20251101"}}"#
        #expect(AgentPlace.lastModel(in: text) == "claude-opus-4-5-20251101")
        #expect(AgentPlace.model(in: ["model": ["id": "claude-haiku-4-5", "display_name": "Haiku"]]) == "claude-haiku-4-5")
    }

    @Test func findsTheRepositoryAboveAFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("agentplace-\(UUID().uuidString)")
        let repo = root.appendingPathComponent("site")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("src/app"), withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(to: repo.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        let place = AgentPlace.place(of: repo.appendingPathComponent("src/app").path)
        #expect(place == AgentPlace.Place(name: "site", isRepository: true, branch: "main"))
        #expect(AgentPlace.place(of: root.path)?.isRepository == false)
    }
}
