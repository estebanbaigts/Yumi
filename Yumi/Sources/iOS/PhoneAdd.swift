import SwiftUI

/// What the « + » of a card adds.
enum PhoneAddKind: String, Identifiable {
    case event, reminder
    var id: String { rawValue }
}

/// What the person asked to delete, waiting for the confirmation.
enum PhoneDeletion {
    case event(AgendaEvent)
    case reminder(ReminderItem)

    var question: String {
        switch self {
        case .event(let event): loc("Supprimer « \(event.title) » de ton agenda ?")
        case .reminder(let reminder): loc("Supprimer le rappel « \(reminder.title) » ?")
        }
    }
}

/// Adds an event or a reminder, in plain fields: a title, a day, an hour.
struct PhoneAddSheet: View {
    let kind: PhoneAddKind
    let today: PhoneToday
    var added: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = PhoneAddSheet.nextHour()
    @State private var allDay = false
    @State private var minutes = 60
    @State private var hasDue = false
    @State private var hasTime = true
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField(kind == .event ? loc("Titre de l'événement") : loc("Ce qu'il faut faire"), text: $title)
                    .focused($focused)
                    .submitLabel(.done)
                if kind == .event {
                    Toggle(loc("Toute la journée"), isOn: $allDay)
                    DatePicker(loc("Quand"), selection: $date,
                               displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    if !allDay {
                        Picker(loc("Durée"), selection: $minutes) {
                            ForEach([15, 30, 45, 60, 90, 120, 180], id: \.self) { value in
                                Text(Duration.seconds(value * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                                    .tag(value)
                            }
                        }
                    }
                } else {
                    Toggle(loc("Une échéance"), isOn: $hasDue.animation())
                    if hasDue {
                        Toggle(loc("À une heure précise"), isOn: $hasTime)
                        DatePicker(loc("Pour"), selection: $date,
                                   displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                    }
                }
            }
            .phoneScreen()
            .navigationTitle(kind == .event ? loc("Nouvel événement") : loc("Nouveau rappel"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(loc("Annuler")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc("Ajouter")) {
                        switch kind {
                        case .event: today.addEvent(title: title, start: date, minutes: minutes, allDay: allDay)
                        case .reminder: today.addReminder(title: title, due: hasDue ? date : nil, hasTime: hasTime)
                        }
                        added()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    /// The next round hour: what people mostly mean.
    static func nextHour(now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? now
    }
}
