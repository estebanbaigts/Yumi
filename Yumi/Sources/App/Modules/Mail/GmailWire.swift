import Foundation
import Network


/// A read-only conversation with Gmail's IMAP server (imap.gmail.com, TLS): log in with an app
/// password, look at the inbox without touching it (EXAMINE), read the headers of the latest
/// mails, log out. Nothing is ever written, moved or marked read.
final class GmailIMAP: @unchecked Sendable {
    enum Failure: Error, Equatable { case connection, refused, answer }

    private let connection: NWConnection
    private var buffer = Data()
    private var tag = 0

    init(host: String = "imap.gmail.com") {
        connection = NWConnection(host: NWEndpoint.Host(host), port: 993, using: .tls)
    }

    /// The latest `count` mails of the inbox, newest first.
    static func latest(address: String, password: String, count: Int = 8) async throws -> [GmailMail] {
        let session = GmailIMAP()
        defer { session.connection.cancel() }
        try await session.open()
        _ = try await session.untagged()
        let login = try await session.command("LOGIN \(quoted(address)) \(quoted(password))")
        guard login.ok else { throw Failure.refused }
        let inbox = try await session.command("EXAMINE INBOX")
        guard inbox.ok, let total = GmailParse.exists(in: String(decoding: inbox.data, as: UTF8.self)) else { throw Failure.answer }
        guard total > 0 else { return [] }
        let first = max(1, total - count + 1)
        let fetch = try await session.command("FETCH \(first):\(total) (UID FLAGS X-GM-THRID X-GM-LABELS BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE REPLY-TO MESSAGE-ID LIST-UNSUBSCRIBE)])")
        guard fetch.ok else { throw Failure.answer }
        _ = try? await session.command("LOGOUT")
        return GmailParse.mails(fromFetch: fetch.data)
    }

    /// The readable text of one mail, its first few thousand bytes, without marking it read.
    static func text(of uid: Int, address: String, password: String) async throws -> String {
        let session = GmailIMAP()
        defer { session.connection.cancel() }
        try await session.open()
        _ = try await session.untagged()
        guard try await session.command("LOGIN \(quoted(address)) \(quoted(password))").ok else { throw Failure.refused }
        guard try await session.command("EXAMINE INBOX").ok else { throw Failure.answer }
        let answer = try await session.command("UID FETCH \(uid) (BODY.PEEK[]<0.80000>)")
        _ = try? await session.command("LOGOUT")
        guard answer.ok else { throw Failure.answer }
        let raw = String(decoding: answer.data, as: UTF8.self)
        // The literal: everything after the first "{n}\r\n"
        guard let open = raw.range(of: "}\r\n") else { return "" }
        return GmailParse.readableText(String(raw[open.upperBound...]))
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: The wire

    private func open() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            connection.stateUpdateHandler = { state in
                guard !once.done else { return }
                switch state {
                case .ready: once.done = true; continuation.resume()
                case .failed, .cancelled: once.done = true; continuation.resume(throwing: Failure.connection)
                case .waiting: once.done = true; continuation.resume(throwing: Failure.connection)
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }
    }

    private func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
                if let data, !data.isEmpty { continuation.resume(returning: data) }
                else if error != nil || complete { continuation.resume(throwing: Failure.connection) }
                else { continuation.resume(returning: Data()) }
            }
        }
    }

    /// The greeting the server sends first.
    private func untagged() async throws -> Data {
        while !buffer.contains(Array("\r\n".utf8)) { buffer += try await receive() }
        let data = buffer
        buffer = Data()
        return data
    }

    /// Sends one command, waits for its tagged answer. `ok` is false for NO and BAD.
    private func command(_ text: String) async throws -> (ok: Bool, data: Data) {
        tag += 1
        let name = "y\(tag)"
        let line = Data("\(name) \(text)\r\n".utf8)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: line, completion: .contentProcessed { error in
                if error != nil { continuation.resume(throwing: Failure.connection) } else { continuation.resume() }
            })
        }
        let marker = Array("\r\n\(name) ".utf8)
        let start = Array("\(name) ".utf8)
        var waited = 0
        while true {
            let bytes = [UInt8](buffer)
            if let at = Self.lineStart(of: marker, start: start, in: bytes),
               let end = Self.index(of: Array("\r\n".utf8), in: bytes, from: at) {
                let status = String(decoding: bytes[at..<end], as: UTF8.self)
                let data = Data(bytes[0..<end])
                buffer = Data(bytes[(end + 2)...])
                return (status.hasPrefix("\(name) OK"), data)
            }
            buffer += try await receive()
            waited += 1
            if waited > 4000 { throw Failure.answer }
        }
    }

    private static func lineStart(of marker: [UInt8], start: [UInt8], in bytes: [UInt8]) -> Int? {
        if bytes.starts(with: start) { return 0 }
        return index(of: marker, in: bytes, from: 0).map { $0 + 2 }
    }

    private static func index(of needle: [UInt8], in bytes: [UInt8], from: Int) -> Int? {
        guard bytes.count >= needle.count, from <= bytes.count - needle.count else { return nil }
        for i in from...(bytes.count - needle.count) where bytes[i] == needle[0] && Array(bytes[i..<i + needle.count]) == needle {
            return i
        }
        return nil
    }
}

/// Sends one mail through Gmail's SMTP server (smtp.gmail.com, TLS), from the person's
/// address, with the same app password. Only called by the "Envoyer" button of a reply the
/// person read: nothing is ever sent on its own.
final class GmailSMTP: @unchecked Sendable {
    enum Failure: Error, Equatable { case connection, refused, rejected(String) }

    private let connection = NWConnection(host: "smtp.gmail.com", port: 465, using: .tls)
    private var buffer = ""

    static func send(from address: String, password: String, to recipient: String, subject: String,
                     inReplyTo messageID: String, body: String) async throws {
        // Each one ends up on a command line: one with a line break could add a recipient.
        guard GmailCompose.isSafeAddress(address), GmailCompose.isSafeAddress(recipient) else {
            throw Failure.rejected(loc("adresse invalide"))
        }
        let smtp = GmailSMTP()
        defer { smtp.connection.cancel() }
        try await smtp.open()
        try await smtp.expect("220")
        try await smtp.say("EHLO yumi.local", expect: "250")
        let plain = Data("\0\(address)\0\(password)".utf8).base64EncodedString()
        do { try await smtp.say("AUTH PLAIN \(plain)", expect: "235") } catch { throw Failure.refused }
        try await smtp.say("MAIL FROM:<\(address)>", expect: "250")
        try await smtp.say("RCPT TO:<\(recipient)>", expect: "250")
        try await smtp.say("DATA", expect: "354")
        let message = GmailCompose.message(from: address, to: recipient, subject: subject, inReplyTo: messageID, body: body)
        try await smtp.say(message + "\r\n.", expect: "250")
        try? await smtp.say("QUIT", expect: "221")
    }

    private func open() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            connection.stateUpdateHandler = { state in
                guard !once.done else { return }
                switch state {
                case .ready: once.done = true; continuation.resume()
                case .failed, .cancelled, .waiting: once.done = true; continuation.resume(throwing: Failure.connection)
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }
    }

    private func say(_ line: String, expect code: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data((line + "\r\n").utf8), completion: .contentProcessed { error in
                if error != nil { continuation.resume(throwing: Failure.connection) } else { continuation.resume() }
            })
        }
        try await expect(code)
    }

    /// Reads one reply (its last line is "250 ..." with a space) and checks its code.
    private func expect(_ code: String) async throws {
        while true {
            let lines = buffer.components(separatedBy: "\r\n")
            if let last = lines.dropLast().last(where: { $0.count >= 4 && $0[$0.index($0.startIndex, offsetBy: 3)] == " " }) {
                buffer = ""
                guard last.hasPrefix(code) else { throw Failure.rejected(last) }
                return
            }
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, complete, error in
                    if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else if error != nil || complete { continuation.resume(throwing: Failure.connection) }
                    else { continuation.resume(returning: Data()) }
                }
            }
            buffer += String(decoding: data, as: UTF8.self)
        }
    }
}

/// Writing the answer as a mail. Pure.
enum GmailCompose {
    /// "Re: Point produit", without piling up "Re: Re:".
    static func replySubject(_ subject: String) -> String {
        subject.lowercased().hasPrefix("re:") ? subject : "Re: " + subject
    }

    /// One plain address: no space, no line break, no bracket or comma that could end a command
    /// line or add a recipient.
    static func isSafeAddress(_ address: String) -> Bool {
        address.utf8.count <= 254
            && address.wholeMatch(of: /[^\s\p{Cc}<>(),;:"\\@]+@[^\s\p{Cc}<>(),;:"\\@]+\.[^\s\p{Cc}<>(),;:"\\@]+/) != nil
    }

    /// The Message-ID when it is one "<...>" without space or line break, else nothing: the
    /// answer then simply starts a new conversation.
    static func safeMessageID(_ id: String) -> String {
        id.utf8.count <= 998 && id.wholeMatch(of: /<[^\s\p{Cc}<>]+>/) != nil ? id : ""
    }

    /// Where an answer goes: the Reply-To, else the sender. Empty when that is not a plain address.
    static func replyAddress(replyTo: String, sender: String) -> String {
        let chosen = replyTo.isEmpty ? sender : replyTo
        return isSafeAddress(chosen) ? chosen : ""
    }

    static func isElsewhere(replyTo: String, sender: String) -> Bool {
        !replyTo.isEmpty && replyTo.lowercased() != sender.lowercased()
    }

    /// The whole message: headers, then the text, lines starting with a dot doubled.
    static func message(from: String, to: String, subject: String, inReplyTo: String, body: String) -> String {
        let inReplyTo = safeMessageID(inReplyTo)
        var headers = [
            "From: <\(from)>",
            "To: <\(to)>",
            "Subject: =?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?=",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=UTF-8",
            "Content-Transfer-Encoding: 8bit",
        ]
        if !inReplyTo.isEmpty {
            headers.append("In-Reply-To: \(inReplyTo)")
            headers.append("References: \(inReplyTo)")
        }
        let text = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
            .map { $0.hasPrefix(".") ? "." + $0 : $0 }
            .joined(separator: "\r\n")
        return headers.joined(separator: "\r\n") + "\r\n\r\n" + text
    }
}
