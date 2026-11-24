import Foundation

/// An answer said aloud: the text without its links (« [titre](url) » keeps its title, a bare
/// address and a « Sources » list go away), and the links apart, to show as buttons.
enum SpokenAnswer {
    static func split(_ answer: String) -> (text: String, links: [URL]) {
        var links: [URL] = []
        func keep(_ raw: String) {
            let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "<>()[].,;:!?»«\"' "))
            if let url = URL(string: cleaned), url.scheme?.hasPrefix("http") == true, !links.contains(url) { links.append(url) }
        }
        var text = answer
        // [title](url): the title stays
        if let markdown = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#) {
            let ns = text as NSString
            for match in markdown.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                keep(ns.substring(with: match.range(at: 2)))
            }
            text = markdown.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "$1")
        }
        // Bare addresses
        if let bare = try? NSRegularExpression(pattern: #"\(?<?https?://[^\s)>\]]+[)>]?"#) {
            let ns = text as NSString
            for match in bare.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                keep(ns.substring(with: match.range))
            }
            text = bare.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }
        // A « Sources » section at the end, and what the links left behind
        var lines = text.components(separatedBy: "\n")
        if let start = lines.lastIndex(where: { line in
            let t = line.trimmingCharacters(in: .whitespaces).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "*#_ "))
            return t.hasPrefix("sources") || t.hasPrefix("source :") || t.hasPrefix("source:")
        }) {
            lines.removeSubrange(start...)
        }
        text = lines
            .map { $0.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { line in !line.isEmpty && line.trimmingCharacters(in: CharacterSet(charactersIn: "-•*–() ")).isEmpty == false }
            .joined(separator: "\n")
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: "()", with: "")
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), links)
    }
}
