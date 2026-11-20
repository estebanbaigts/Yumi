import Foundation

/// The iPhone's planner: the simple mode first, the model only when the simple mode did not
/// understand. The simple mode keeps the person's own words (« bar avec les copains »), where a
/// small model may translate or rephrase them; the model takes the requests it cannot read.
struct PhonePlanner: AgentPlanner {
    var simple: SimplePlanner
    var llm: LLMAgentPlanner

    var name: String { "phone" }

    func propose(for request: AgentRequest, tools: [ToolDescriptor]) async throws(AgentError) -> PlanProposal {
        let plain = simple.proposal(for: request.trimmedIntent, tools: tools.map(\.id))
        if plain.steps != nil { return plain }
        do {
            return try await llm.propose(for: request, tools: tools)
        } catch .noProvider {
            return plain
        } catch .cancelled {
            throw .cancelled
        } catch {
            return plain
        }
    }
}
