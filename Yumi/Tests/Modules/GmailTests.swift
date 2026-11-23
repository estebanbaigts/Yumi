import Testing
import Foundation

@Suite struct GmailParseTests {
    private func fetch(_ answers: [(attrs: String, headers: String, after: String)]) -> Data {
        var text = "* 12 EXISTS\r\n"
        for (i, answer) in answers.enumerated() {
            let headers = answer.headers.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n\r\n"
            text += "* \(i + 1) FETCH (\(answer.attrs) BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {\(headers.utf8.count)}\r\n\(headers)\(answer.after))\r\n"
        }
        return Data((text + "y3 OK Success\r\n").utf8)
    }

    @Test func readsTheMailsNewestFirstWithTheirImportance() {
        let data = fetch([
            ("UID 40 FLAGS (\\Seen) X-GM-THRID 1790000000000000001 X-GM-LABELS (\\Inbox)", "From: News <newsletter@shop.fr>\nSubject: Promo\nList-Unsubscribe: <mailto:x>\nDate: Tue, 13 Oct 2026 09:00:00 +0200", ""),
            ("UID 41 FLAGS () X-GM-THRID 1790000000000000002 X-GM-LABELS (\\Inbox \"\\\\Important\")", "From: =?UTF-8?B?TMOpYSBNYXJ0aW4=?= <lea@x.fr>\nSubject: =?UTF-8?Q?Point_produit_d=C3=A9cal=C3=A9?=\nReply-To: lea.pro@x.fr\nMessage-ID: <abc@x.fr>\nDate: Tue, 13 Oct 2026 14:02:11 +0200", ""),
        ])
        let mails = GmailParse.mails(fromFetch: data)
        #expect(mails.map(\.uid) == [41, 40])
        #expect(mails[0].from == "Léa Martin")
        #expect(mails[0].subject == "Point produit décalé")
        #expect(mails[0].unread && mails[0].important && !mails[0].bulk)
        #expect(mails[0].replyAddress == "lea.pro@x.fr" && mails[0].messageID == "<abc@x.fr>")
        #expect(mails[0].date != nil)
        #expect(!mails[1].unread && mails[1].bulk && !mails[1].important)
        #expect(GmailParse.exists(in: "* FLAGS ()\r\n* 12 EXISTS\r\n") == 12)
    }

    @Test func aMachineIsNeverImportant() {
        #expect(GmailParse.isAutomatic("no-reply@github.com"))
        #expect(GmailParse.isAutomatic("notifications@vercel.com"))
        #expect(!GmailParse.isAutomatic("paul@gmail.com"))
        #expect(GmailParse.address("Léa <lea@x.fr>") == "lea@x.fr")
        #expect(GmailParse.sender("<lea@x.fr>") == "lea@x.fr")
    }

    @Test func keepsOnlyTheNewTextOfABody() {
        let raw = "--b1\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nSalut, on d=C3=A9cale =C3=A0 jeudi ?\r\n\r\nLe lun. 12 oct. 2026 à 10:00, Esteban a écrit :\r\n> ok\r\n--b1\r\nContent-Type: text/html\r\n\r\n<p>x</p>\r\n--b1--"
        #expect(GmailParse.readableText(raw) == "Salut, on décale à jeudi ?")
    }

    @Test func anAnswerStaysInTheConversation() {
        #expect(GmailCompose.replySubject("Point produit") == "Re: Point produit")
        #expect(GmailCompose.replySubject("RE: Point") == "RE: Point")
        let message = GmailCompose.message(from: "a@gmail.com", to: "b@x.fr", subject: "Re: Point", inReplyTo: "<abc@x.fr>", body: "Oui\n.fin")
        #expect(message.contains("In-Reply-To: <abc@x.fr>\r\nReferences: <abc@x.fr>"))
        #expect(message.hasSuffix("\r\n\r\nOui\r\n..fin"))
    }

    @Test func aReplyToCannotSmuggleARecipient() {
        // "=?UTF-8?B?...?=" decodes to "x@evil.fr>\r\nRCPT TO:<spy@evil.fr": a line break on the RCPT line.
        let smuggled = "=?UTF-8?B?" + Data("x@evil.fr>\r\nRCPT TO:<spy@evil.fr".utf8).base64EncodedString() + "?="
        let data = fetch([
            ("UID 50 FLAGS () X-GM-LABELS (\\Inbox)", "From: Bank <service@bank.fr>\nSubject: Urgent\nReply-To: <\(smuggled)>\nMessage-ID: <a@b.fr>\nDate: Tue, 13 Oct 2026 14:02:11 +0200", ""),
        ])
        let mail = GmailParse.mails(fromFetch: data)[0]
        #expect(mail.replyAddress.isEmpty)
        #expect(!mail.replyAddress.contains("\n") && !mail.replyAddress.contains("\r"))
    }

    @Test func aReplyToElsewhereIsPointedOut() {
        let data = fetch([
            ("UID 51 FLAGS () X-GM-LABELS (\\Inbox)", "From: Bank <service@bank.fr>\nSubject: Urgent\nReply-To: <help@other.fr>\nDate: Tue, 13 Oct 2026 14:02:11 +0200", ""),
            ("UID 52 FLAGS () X-GM-LABELS (\\Inbox)", "From: Léa <lea@x.fr>\nSubject: Point\nReply-To: LEA@x.fr\nDate: Tue, 13 Oct 2026 14:02:11 +0200", ""),
        ])
        let mails = GmailParse.mails(fromFetch: data)
        #expect(mails[1].replyAddress == "help@other.fr" && mails[1].replyElsewhere)
        #expect(!mails[0].replyElsewhere)
    }

    @Test func onlyPlainAddressesAndMessageIDsAreUsed() {
        #expect(GmailCompose.isSafeAddress("lea.pro+tag@x.fr"))
        for bad in ["", "lea@x.fr\r\nRCPT TO:<spy@evil.fr>", "lea@x.fr\n", "a@b.fr>,<c@d.fr", "a b@x.fr", "a@b", "a@@b.fr", "a@b.fr\u{0}"] {
            #expect(!GmailCompose.isSafeAddress(bad), "\(bad.debugDescription)")
        }
        #expect(GmailCompose.safeMessageID("<abc@x.fr>") == "<abc@x.fr>")
        #expect(GmailCompose.safeMessageID("<abc@x.fr>\nBcc: spy@evil.fr") == "")
        let message = GmailCompose.message(from: "a@gmail.com", to: "b@x.fr", subject: "Re: x", inReplyTo: "<a@b>\rBcc: spy@evil.fr", body: "Oui\r.\rfin")
        #expect(!message.contains("Bcc"))
        #expect(!message.contains("\r.\r"))
    }

    @Test func theIslandPutsTheImportantFirst() {
        var plain = GmailMail(uid: 2, from: "Shop", subject: "Promo", date: nil, unread: true, thread: nil)
        plain.bulk = true
        var important = GmailMail(uid: 1, from: "Léa", subject: "Contrat", date: nil, unread: true, thread: nil)
        important.important = true
        let snapshot = GmailSummary.snapshot(mails: [plain, important], connection: .connected, now: .now)
        #expect(snapshot.rows.map(\.id) == ["1", "2"])
        #expect(snapshot.needsAttention)
        #expect(snapshot.title == "Contrat")
    }
}

@Suite struct MusicTitlesTests {
    @Test func readsYouTubeMusicAndDeezerTitles() {
        let yt = MusicTitles.parse("Lueur • Halo Nord - YouTube Music - Google Chrome")
        #expect(yt?.player == .youtubeMusic && yt?.title == "Lueur" && yt?.artist == "Halo Nord")
        let deezer = MusicTitles.parse("Lueur - Halo Nord - Deezer")
        #expect(deezer?.player == .deezer && deezer?.title == "Lueur" && deezer?.artist == "Halo Nord")
        let app = MusicTitles.parse("Lueur - Halo Nord", appName: "Deezer")
        #expect(app?.player == .deezer)
    }

    @Test func ignoresAPlayerWithNothingOn() {
        #expect(MusicTitles.parse("YouTube Music - Google Chrome") == nil)
        #expect(MusicTitles.parse("Deezer", appName: "Deezer") == nil)
        #expect(MusicTitles.parse("Inbox - Gmail - Google Chrome") == nil)
        #expect(!MusicPlayer.deezer.isScriptable && MusicPlayer.spotify.isScriptable)
    }

    @Test func htmlMailShowsItsTextNotItsStyles() {
        let html = "<html><head><style>.ReadMsgBody{width:100%}</style></head><body><p>Bonjour Esteban,</p><p>Une offre pour toi.</p></body></html>"
        let raw = "Delivered-To: a@b.fr\r\nContent-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
            + Data(html.utf8).base64EncodedString()
        let text = GmailParse.readableText(raw)
        #expect(text == "Bonjour Esteban,\nUne offre pour toi.")
    }
}
