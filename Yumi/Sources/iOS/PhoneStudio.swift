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
}
