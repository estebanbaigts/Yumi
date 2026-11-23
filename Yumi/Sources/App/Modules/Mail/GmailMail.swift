import Foundation

/// One mail of the inbox (Mail's unified inbox or Gmail's), as the island shows it: who, what, when, read or not.
struct GmailMail: Equatable, Sendable, Identifiable {
    var uid: Int
    /// The sender's name, or their address without a name.
    var from: String
    var subject: String
    var date: Date?
    var unread: Bool
    /// Gmail's thread id, to open the conversation in the browser.
    var thread: UInt64?
    /// Marked important by Gmail, and not a newsletter or an automatic mail.
    var important = false
    /// A newsletter or an automatic mail (List-Unsubscribe, no-reply sender).
    var bulk = false
    /// Where an answer goes: Reply-To, else the sender's address.
    var replyAddress = ""
    /// The Reply-To names another address than the sender's: the island says so before sending.
    var replyElsewhere = false
    /// The Message-ID, so an answer stays in the conversation.
    var messageID = ""
    /// The account in Mail ("iCloud", "Pro"...); empty for Gmail by app password.
    var account = ""
    /// Where Mail showed it at the last look: the account's inbox (1-based) and the mail's place in
    /// it. Reaches the mail in one Apple Event; checked against `messageID`, as new mail shifts it.
    var mailAppPlace: MailAppPlace?
    /// Where it was read: Mail opens it in Mail, Gmail in the browser.
    var source = MailSource.gmail

    var id: Int { uid }

    /// The conversation in Gmail's web page.
    var url: URL? {
        guard let thread else { return URL(string: "https://mail.google.com/mail/u/0/#inbox") }
        return URL(string: "https://mail.google.com/mail/u/0/#inbox/" + String(thread, radix: 16))
    }
}

struct MailAppPlace: Equatable, Sendable {
    var mailbox: Int
    var index: Int
}

/// Reading what Gmail's IMAP server answers. Pure: no network here.
private extension String {
    /// A base64 text cut at a length the decoder accepts (the fetch may stop mid-way).
    var base64Trimmed: String { String(prefix(count - count % 4)) }
}

enum GmailParse {

    /// The number of mails in the mailbox, from the `* 123 EXISTS` line of SELECT or EXAMINE.
    static func exists(in response: String) -> Int? {
        for line in response.components(separatedBy: "\r\n") {
            let parts = line.split(separator: " ")
            if parts.count >= 3, parts[0] == "*", parts[2] == "EXISTS" { return Int(parts[1]) }
        }
        return nil
    }

    /// The mails of a FETCH answer asking for `UID FLAGS X-GM-THRID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)]`,
    /// newest first.
    static func mails(fromFetch data: Data) -> [GmailMail] {
        let bytes = [UInt8](data)
        var mails: [GmailMail] = []
        var index = 0
        // Each answer is "* n FETCH (...)", with the headers sent as a literal "{size}\r\n<bytes>"
        while let start = find(Array("* ".utf8), in: bytes, from: index) {
            guard let lineEnd = find(Array("\r\n".utf8), in: bytes, from: start) else { break }
            let head = String(decoding: bytes[start..<lineEnd], as: UTF8.self)
            guard head.contains(" FETCH ") else { index = lineEnd + 2; continue }
            var attributes = head
            var headers = ""
            var next = lineEnd + 2
            if let open = head.lastIndex(of: "{"), let close = head.lastIndex(of: "}"), open < close,
               let size = Int(head[head.index(after: open)..<close]) {
                let end = min(bytes.count, next + size)
                headers = String(decoding: bytes[next..<end], as: UTF8.self)
                next = end
                // What follows the literal ends the answer: " UID 12 FLAGS (\Seen))"
                if let after = find(Array("\r\n".utf8), in: bytes, from: next) {
                    attributes += String(decoding: bytes[next..<after], as: UTF8.self)
                    next = after + 2
                }
            }
            index = next
            guard let uid = number(after: "UID ", in: attributes) else { continue }
            let fields = headerFields(headers)
            let flags = flagsList(in: attributes)
            let labels = labelsList(in: attributes)
            let fromField = decode(fields["from"] ?? "")
            let bulk = fields["list-unsubscribe"] != nil || isAutomatic(address(fromField))
            var mail = GmailMail(uid: uid,
                                   from: sender(decode(fields["from"] ?? "")),
                                   subject: decode(fields["subject"] ?? "").trimmingCharacters(in: .whitespaces),
                                   date: fields["date"].flatMap(date),
                                   unread: !flags.contains("\\Seen"),
                                   thread: number(after: "X-GM-THRID ", in: attributes).map(UInt64.init)
                                       ?? bigNumber(after: "X-GM-THRID ", in: attributes))
            mail.bulk = bulk
            mail.important = labels.contains("\\Important") && !bulk
            // Both come from whoever wrote the mail: an address that is not one plain address is
            // dropped, so nothing can be answered to it.
            let replyTo = address(decode(fields["reply-to"] ?? ""))
            mail.replyAddress = GmailCompose.replyAddress(replyTo: replyTo, sender: address(fromField))
            mail.replyElsewhere = GmailCompose.isElsewhere(replyTo: replyTo, sender: address(fromField))
            mail.messageID = GmailCompose.safeMessageID((fields["message-id"] ?? "").trimmingCharacters(in: .whitespaces))
            mails.append(mail)
        }
        return mails.sorted { $0.uid > $1.uid }
    }

    // MARK: Headers

    /// The header fields, lower-cased names, folded lines joined.
    static func headerFields(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        var current: String?
        for line in text.components(separatedBy: "\r\n") {
            if line.isEmpty { continue }
            if line.first == " " || line.first == "\t", let name = current {
                fields[name, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                let name = line[..<colon].lowercased()
                fields[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                current = name
            }
        }
        return fields
    }

    /// RFC 2047: "=?UTF-8?B?...?=" and "=?ISO-8859-1?Q?...?=" become text. Spaces between two
    /// encoded words are dropped, as the RFC says.
    static func decode(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#) else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        var previousWasEncoded = false
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let between = ns.substring(with: NSRange(location: last, length: match.range.location - last))
            if !(previousWasEncoded && between.trimmingCharacters(in: .whitespaces).isEmpty) { result += between }
            let charset = ns.substring(with: match.range(at: 1)).lowercased()
            let mode = ns.substring(with: match.range(at: 2)).uppercased()
            let payload = ns.substring(with: match.range(at: 3))
            let encoding: String.Encoding = charset.contains("8859") || charset.contains("latin") ? .isoLatin1
                : charset.contains("1252") ? .windowsCP1252 : .utf8
            var data: Data?
            if mode == "B" {
                data = Data(base64Encoded: payload.padding(toLength: (payload.count + 3) / 4 * 4, withPad: "=", startingAt: 0))
            } else {
                data = quotedPrintable(payload.replacingOccurrences(of: "_", with: " "))
            }
            result += data.flatMap { String(data: $0, encoding: encoding) } ?? payload
            last = match.range.location + match.range.length
            previousWasEncoded = true
        }
        result += ns.substring(from: last)
        return result
    }

    static func quotedPrintable(_ text: String) -> Data {
        var out = Data()
        let bytes = Array(text.utf8)
        var i = 0
        while i < bytes.count {
            if bytes[i] == UInt8(ascii: "="), i + 2 < bytes.count,
               let value = UInt8(String(decoding: bytes[i + 1...i + 2], as: UTF8.self), radix: 16) {
                out.append(value)
                i += 3
            } else {
                out.append(bytes[i])
                i += 1
            }
        }
        return out
    }

    /// "Léa Martin <lea@x.fr>" → "Léa Martin"; "<lea@x.fr>" or "lea@x.fr" → "lea@x.fr".
    static func sender(_ from: String) -> String {
        let trimmed = from.trimmingCharacters(in: .whitespaces)
        if let open = trimmed.firstIndex(of: "<") {
            let name = trimmed[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            if !name.isEmpty { return name }
            return trimmed[trimmed.index(after: open)...].trimmingCharacters(in: CharacterSet(charactersIn: "> "))
        }
        return trimmed
    }

    /// RFC 2822 dates: "Tue, 13 Oct 2026 14:02:11 +0200", with or without the day name or seconds.
    static func date(_ text: String) -> Date? {
        let cleaned = text.replacingOccurrences(of: #"\s*\([^)]*\)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z", "d MMM yyyy HH:mm Z"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) { return date }
        }
        return nil
    }

    // MARK: Small readers

    private static func find(_ needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard !needle.isEmpty, start <= bytes.count - needle.count else { return nil }
        var i = start
        while i <= bytes.count - needle.count {
            if bytes[i] == needle[0], Array(bytes[i..<i + needle.count]) == needle { return i }
            i += 1
        }
        return nil
    }

    private static func number(after key: String, in text: String) -> Int? {
        guard let range = text.range(of: key) else { return nil }
        return Int(text[range.upperBound...].prefix { $0.isNumber })
    }

    private static func bigNumber(after key: String, in text: String) -> UInt64? {
        guard let range = text.range(of: key) else { return nil }
        return UInt64(text[range.upperBound...].prefix { $0.isNumber })
    }

    /// "Léa <lea@x.fr>" → "lea@x.fr".
    static func address(_ from: String) -> String {
        let trimmed = from.trimmingCharacters(in: .whitespaces)
        if let open = trimmed.firstIndex(of: "<"), let close = trimmed.lastIndex(of: ">"), open < close {
            return String(trimmed[trimmed.index(after: open)..<close])
        }
        return trimmed
    }

    /// A sender that is a machine: no-reply, notifications, newsletters.
    static func isAutomatic(_ address: String) -> Bool {
        let local = address.lowercased().split(separator: "@").first.map(String.init) ?? ""
        return ["noreply", "no-reply", "donotreply", "do-not-reply", "notification", "notifications", "newsletter", "news",
                "mailer-daemon", "bounce", "info", "marketing", "updates", "digest"].contains { local.contains($0) }
    }

    /// The Gmail labels of `X-GM-LABELS (\Inbox \Important "Mon label")`.
    static func labelsList(in text: String) -> [String] {
        guard let range = text.range(of: "X-GM-LABELS (") else { return [] }
        return text[range.upperBound...].prefix { $0 != ")" }.split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\\\"")) }
            .map { $0.hasPrefix("Important") ? "\\Important" : $0 }
    }

    /// The readable text of a mail body as the server sends it: the plain part when the mail has
    /// one, HTML tags removed otherwise, quoted-printable decoded, the quoted history dropped.
    /// One part of a multipart mail: its headers and its body, up to the next boundary.
    static func part(_ type: String, in raw: String) -> (headers: String, body: String)? {
        guard let found = raw.range(of: "Content-Type: \(type)", options: .caseInsensitive) else { return nil }
        // The part's headers start after the boundary line before it
        let before = raw[..<found.lowerBound]
        let headerStart = before.range(of: "\r\n--", options: .backwards)?.upperBound ?? raw.startIndex
        let rest = raw[found.lowerBound...]
        guard let blank = rest.range(of: "\r\n\r\n") else { return nil }
        let headers = String(raw[headerStart..<blank.lowerBound])
        let body = rest[blank.upperBound...]
        return (headers, String(body.components(separatedBy: "\r\n--").first ?? String(body)))
    }

    static func readableText(_ raw: String) -> String {
        var text = raw
        var encoding = raw
        // A multipart mail: the first text/plain part, else the first text/html one
        if let part = part("text/plain", in: raw) ?? part("text/html", in: raw) {
            text = part.body
            encoding = part.headers
        } else if raw.hasPrefix("Received:") || raw.hasPrefix("Delivered-To:") || raw.hasPrefix("Return-Path:"),
                  let blank = raw.range(of: "\r\n\r\n") {
            // A whole message without a type: its headers go
            encoding = String(raw[..<blank.lowerBound])
            text = String(raw[blank.upperBound...])
        }
        if encoding.range(of: "base64", options: .caseInsensitive) != nil,
           let data = Data(base64Encoded: String(text.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
                .prefix { $0 != "-" }.dropLast(0)).base64Trimmed) {
            text = String(decoding: data, as: UTF8.self)
        } else if encoding.range(of: "quoted-printable", options: .caseInsensitive) != nil || text.contains("=\r\n") {
            text = String(decoding: quotedPrintable(text.replacingOccurrences(of: "=\r\n", with: "")), as: UTF8.self)
        }
        // HTML: what is never read (styles, scripts, the head) goes before the tags
        for block in ["style", "script", "head", "title"] {
            text = text.replacingOccurrences(of: "<\(block)[^>]*>[\\s\\S]*?</\(block)>", with: " ",
                                             options: [.regularExpression, .caseInsensitive])
        }
        text = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<(br|/p|/div|/tr|/h[1-6]|/li)[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, char) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                               ("&#39;", "'"), ("&rsquo;", "’"), ("&eacute;", "é"), ("&egrave;", "è"), ("&agrave;", "à"),
                               ("&ccedil;", "ç"), ("&ecirc;", "ê"), ("&zwnj;", ""), ("&#8203;", "")] {
            text = text.replacingOccurrences(of: entity, with: char, options: .caseInsensitive)
        }
        text = text.replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") { continue }
            // "Le mar. 13 oct. 2026 à 14:02, Léa a écrit :" / "On ... wrote:" starts the history
            if (trimmed.hasPrefix("Le ") && trimmed.hasSuffix("a écrit :")) || (trimmed.hasPrefix("On ") && trimmed.hasSuffix("wrote:")) { break }
            if trimmed.hasPrefix("--") && trimmed.count > 10 && !trimmed.contains(" ") { continue }
            lines.append(trimmed)
        }
        return lines.joined(separator: "\n").replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func flagsList(in text: String) -> [String] {
        guard let range = text.range(of: "FLAGS (") else { return [] }
        let rest = text[range.upperBound...]
        return rest.prefix { $0 != ")" }.split(separator: " ").map(String.init)
    }
}

/// Where the mails come from. Mail is the default; Gmail with an app password stays an option.
enum MailSource: String, CaseIterable, Sendable {
    case mailApp, gmail

    static let defaultsKey = "mail.source"

    /// Mail needs Apple Events, which the App Store build does not have.
    static var mailAppAvailable: Bool {
        #if APPSTORE
        return false
        #else
        return true
        #endif
    }

    /// The person's choice. Someone who had already connected Gmail before this choice existed
    /// keeps Gmail; everyone else starts with Mail.
    static func current(in defaults: UserDefaults = .standard, gmailConnected: Bool) -> MailSource {
        guard mailAppAvailable else { return .gmail }
        if let raw = defaults.string(forKey: defaultsKey), let source = MailSource(rawValue: raw) { return source }
        return gmailConnected ? .gmail : .mailApp
    }
}
