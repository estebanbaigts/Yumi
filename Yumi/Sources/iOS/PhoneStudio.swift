import Foundation

/// Filming mode on the iPhone (`YUMI_STUDIO=1`, as on the Mac): made-up content, nothing real
/// read or written, no permission asked. Also what the previews and the simulator show.
enum PhoneStudio {
    private static func today(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    static var conversation: [PhoneMessage] {
        [
            PhoneMessage(role: .person, text: "Qu'est-ce que j'ai cet après-midi ?", date: today(9, 12)),
            PhoneMessage(role: .yumi, text: "Le point avec Camille à 14 h, puis rien jusqu'au soir. Tu veux que je te le rappelle un quart d'heure avant ?", date: today(9, 12)),
            PhoneMessage(role: .person, text: "Oui, et rappelle-moi d'acheter du pain en rentrant", date: today(9, 13)),
            PhoneMessage(role: .yumi, text: "C'est noté : « Acheter du pain », ce soir à 18 h.", date: today(9, 13)),
        ]
    }

    static var events: [AgendaEvent] {
        [
            AgendaEvent(id: "studio-1", title: "Point avec Camille", start: today(14), end: today(14, 30),
                        isAllDay: false, location: "Visio", joinURL: nil),
            AgendaEvent(id: "studio-2", title: "Sport", start: today(18, 30), end: today(19, 30),
                        isAllDay: false, location: "", joinURL: nil),
        ]
    }

    /// A week with something on three days.
    static var week: [(day: Date, events: [AgendaEvent])] {
        let calendar = Calendar.current
        func on(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today(hour, minute)) ?? Date()
        }
        return [
            (calendar.startOfDay(for: Date()), events),
            (calendar.startOfDay(for: on(1, 0)), [AgendaEvent(id: "studio-3", title: "Dentiste", start: on(1, 10), end: on(1, 10, 30),
                                                             isAllDay: false, location: "", joinURL: nil)]),
            (calendar.startOfDay(for: on(3, 0)), [AgendaEvent(id: "studio-4", title: "Anniversaire de Léa", start: on(3, 0), end: on(3, 23, 59),
                                                             isAllDay: true, location: "", joinURL: nil),
                                                 AgendaEvent(id: "studio-5", title: "Dîner chez Léa", start: on(3, 20), end: on(3, 23),
                                                             isAllDay: false, location: "", joinURL: nil)]),
        ]
    }

    static var reminders: [ReminderItem] {
        [
            ReminderItem(id: "studio-r1", title: "Acheter du pain", due: today(18), hasTime: true),
            ReminderItem(id: "studio-r2", title: "Appeler le dentiste", due: nil, hasTime: false),
        ]
    }

    static let notes = ["Idée : un mode nuit pour Yumi", "Livre conseillé par Léa"]

    static var weather: WeatherReport {
        WeatherReport(temperature: 17, code: 2,
                      hours: (0..<6).map { .init(time: today(10 + $0), rainChance: [0, 5, 10, 30, 20, 5][$0]) })
    }

    /// What the Mac would show through the link.
    static var mac: LinkSnapshot {
        LinkSnapshot(deviceName: "MacBook Pro", sentAt: Date(),
                     sessions: [
                        LinkSession(id: "s1", agent: "Claude Code", project: "Yumi", status: "travaille", updatedAt: Date()),
                        LinkSession(id: "s2", agent: "Codex", project: "site", status: "terminé", updatedAt: Date()),
                     ],
                     approvals: [LinkApproval(id: "studio-a1", sessionID: "s1", summary: "pousser sur le serveur git",
                                              fingerprint: "studio", expiresAt: Date().addingTimeInterval(110))],
                     github: ["PR #30 ouverte : refonte de l'île", "main : 3 commits poussés"])
    }

    static var mails: [GmailMail] {
        [
            GmailMail(uid: 3, from: "Camille Martin", subject: "Point de cet après-midi", date: today(8, 47), unread: true,
                      replyAddress: "camille@example.com", messageID: "<studio-3@example.com>"),
            GmailMail(uid: 2, from: "Léa", subject: "Dîner jeudi ?", date: today(7, 30), unread: true,
                      replyAddress: "lea@example.com", messageID: "<studio-2@example.com>"),
            GmailMail(uid: 1, from: "La Poste", subject: "Votre colis arrive demain", date: today(6, 5), unread: false,
                      bulk: true, replyAddress: "", messageID: ""),
        ]
    }

    static let mailText = "Salut Esteban,\n\nOn garde 14 h pour le point ? Je voudrais qu'on regarde la maquette de l'écran d'accueil ensemble.\n\nÀ tout à l'heure,\nCamille"
}
