import SwiftUI

/// The past conversations with Yumi, newest first: a touch reopens one, a swipe forgets it.
struct PhoneHistoryView: View {
    let chat: PhoneChat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if chat.history.isEmpty {
                    Text(loc("Aucune discussion passée. « Nouvelle discussion » range celle en cours ici."))
                        .font(.system(size: u(13))).foregroundStyle(PhoneTheme.gray)
                        .listRowBackground(Color.clear)
                }
                ForEach(chat.history) { past in
                    Button {
                        withAnimation { chat.reopen(past) }
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: u(3)) {
                            Text(past.title).font(.system(size: u(14), weight: .semibold)).lineLimit(1)
                            Text("\(past.date.formatted(.relative(presentation: .named))) · \(loc("\(past.messages.count) messages"))")
                                .font(.system(size: u(11.5))).foregroundStyle(PhoneTheme.gray)
                        }
                    }
                    .listRowBackground(PhoneTheme.ink)
                    .swipeActions { Button(loc("Oublier"), role: .destructive) { chat.forget(past) } }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle(loc("Historique"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(loc("Fermer")) { dismiss() } } }
            .onAppear { chat.loadHistory() }
        }
        .presentationBackground(.black)
    }
}
