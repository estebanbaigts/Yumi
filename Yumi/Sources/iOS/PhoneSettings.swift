import SwiftUI

/// Réglages: Yumi, Comptes, Accès, then the app itself. Each row says where it stands.
struct PhoneSettingsView: View {
    @Bindable var phone: Phone
    @State private var language = AppLanguage.stored()
    @State private var confirmClear = false
    @State private var connecting = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section(loc("Yumi")) {
                    link(loc("Voix"), PhoneVoiceChoice.current.phoneLabel, 0xF58AD9) { phone.go(.yumi) }
                    push(loc("Mémoire"), loc("\(phone.memoryBook.entries.count) souvenirs"), 0x4EE6B0) { PhoneMemoryView(phone: phone) }
                    row(loc("Moteur"), PhoneChat.whyNoModel(AppleModelAvailability.current) == nil ? loc("Modèle d'Apple") : loc("Indisponible"), 0x8B6CFF)
                }
                section(loc("Comptes")) {
                    if phone.mail.isConnected {
                        link(loc("Gmail"), phone.mail.address.isEmpty ? loc("Relié") : phone.mail.address, 0xFF8A7A) { connecting = true }
                    } else {
                        link(loc("Gmail"), loc("Relier"), 0xFF8A7A) { connecting = true }
                    }
                    link(loc("Mon Mac"), phone.linkOn ? (phone.mac?.deviceName ?? loc("En attente du Mac")) : loc("Relier"), 0xC9D1D9) { phone.go(.mac) }
                }
                section(loc("Accès")) {
                    link(loc("Notifications"), loc("Demandes"), 0xFFB86B, action: openSettings)
                    link(loc("Agenda et rappels"), phone.today.calendarAccess == .granted ? loc("Autorisé") : loc("Refusé"), 0xFF8A7A, action: openSettings)
                    link(loc("Localisation (météo)"), Self.location(phone.today.weather), 0x7FD8FF, action: openSettings)
                    link(loc("Micro et voix"), phone.listener.access == .denied ? loc("Refusé") : loc("Pour parler"), 0x7FD8FF, action: openSettings)
                }
                section(loc("App")) {
                    HStack(spacing: u(10)) {
                        dot(0x9D8BFF)
                        Text(loc("Langue")).frame(maxWidth: .infinity, alignment: .leading)
                        Picker(loc("Langue"), selection: Binding(get: { language }, set: { language = $0; AppLanguage.choose($0) })) {
                            Text(loc("Automatique")).tag(AppLanguage.automatic)
                            Text(verbatim: "Français").tag(AppLanguage.french)
                            Text(verbatim: "English").tag(AppLanguage.english)
                        }
                        .tint(PhoneTheme.gray)
                    }
                    .font(.system(size: u(15))).padding(.horizontal, u(14)).frame(minHeight: u(46))
                    toggle(loc("Dans la Dynamic Island"), 0x5B8CFF, $phone.islandOn)
                    toggle(loc("Sons"), 0x3DDC97, $phone.soundOn)
                    toggle(loc("Yumi te regarde"), 0xF58AD9, $phone.watchesOn)
                    if phone.watchesOn {
                        toggle(loc("Suivre mon visage (caméra)"), 0xF58AD9, $phone.watchesFace)
                    }
                    #if DEBUG
                    toggle(loc("Mode tournage au prochain lancement"), 0xFFB547, $phone.studioNextLaunch)
                    #endif
                    Button { confirmClear = true } label: {
                        HStack(spacing: u(10)) {
                            dot(0xFF453A)
                            Text(loc("Effacer la conversation")).foregroundStyle(PhoneTheme.refuse)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(loc("\(phone.chat.messages.count) messages")).foregroundStyle(PhoneTheme.gray)
                        }
                        .font(.system(size: u(15))).padding(.horizontal, u(14)).frame(minHeight: u(46))
                    }
                    .buttonStyle(.plain)
                    .disabled(phone.chat.messages.isEmpty)
                }
                if language.code.map({ $0 != AppLanguage.current }) ?? (AppLanguage.resolve(Locale.preferredLanguages.first) != AppLanguage.current) {
                    Text(loc("La nouvelle langue s'applique au prochain lancement de Yumi."))
                        .font(.system(size: u(11))).foregroundStyle(PhoneTheme.gray).padding(.horizontal, u(4)).padding(.top, u(6))
                }
            }
            .padding(.horizontal, u(14))
            .padding(.bottom, u(110))
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $connecting) { PhoneMailConnect(mail: phone.mail) }
        .confirmationDialog(loc("Effacer toute la conversation avec Yumi ?"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(loc("Effacer"), role: .destructive) { phone.chat.clear() }
        }
    }

    private static func location(_ state: WeatherState) -> String {
        switch state {
        case .needsLocation(.denied): loc("Refusé")
        case .needsLocation: loc("Pas encore")
        default: loc("Autorisée")
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    // MARK: Pieces

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        Text(title).phoneEyebrow(PhoneTheme.gray).padding(.horizontal, u(4)).padding(.top, u(14)).padding(.bottom, u(6))
        VStack(spacing: 0) {
            Group(subviews: rows()) { items in
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Rectangle().fill(YumiRGB(hex: 0xAA96FF).color.opacity(0.1)).frame(height: 1) }
                    item
                }
            }
        }
        .background(YumiRGB(hex: 0x8C78FF).color.opacity(0.07), in: RoundedRectangle(cornerRadius: u(20), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: u(20), style: .continuous).strokeBorder(YumiRGB(hex: 0xAA96FF).color.opacity(0.12), lineWidth: 1))
    }

    private func dot(_ hex: UInt32) -> some View {
        Circle().fill(YumiRGB(hex: hex).color).frame(width: u(10), height: u(10))
            .shadow(color: YumiRGB(hex: hex).color, radius: u(5))
    }

    private func row(_ title: String, _ value: String, _ hex: UInt32, chevron: Bool = false) -> some View {
        HStack(spacing: u(10)) {
            dot(hex)
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
            Text(value + (chevron ? " ›" : "")).foregroundStyle(PhoneTheme.gray).lineLimit(1)
        }
        .font(.system(size: u(15)))
        .padding(.horizontal, u(14)).frame(minHeight: u(46))
        .contentShape(Rectangle())
    }

    private func link(_ title: String, _ value: String, _ hex: UInt32, action: @escaping () -> Void) -> some View {
        Button(action: action) { row(title, value, hex, chevron: true) }.buttonStyle(.plain)
    }

    private func push(_ title: String, _ value: String, _ hex: UInt32, @ViewBuilder to: () -> some View) -> some View {
        NavigationLink { to() } label: { row(title, value, hex, chevron: true) }.buttonStyle(.plain)
    }

    private func toggle(_ title: String, _ hex: UInt32, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) { HStack(spacing: u(10)) { dot(hex); Text(title) } }
            .tint(PhoneTheme.violet)
            .font(.system(size: u(15)))
            .padding(.horizontal, u(14)).frame(minHeight: u(46))
    }
}

/// What Yumi remembers; a swipe forgets.
struct PhoneMemoryView: View {
    let phone: Phone

    var body: some View {
        List {
            if phone.memoryBook.entries.isEmpty {
                Text(loc("Rien pour l'instant.")).foregroundStyle(PhoneTheme.gray)
            }
            ForEach(phone.memoryBook.entries) { entry in
                Text(entry.text)
                    .swipeActions { Button(loc("Oublier"), role: .destructive) { phone.forget(entry) } }
            }
            .listRowBackground(PhoneTheme.ink)
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle(loc("Ce que je sais de toi"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The voices of the iPhone: its own, or ElevenLabs' woman and man (with the person's key).
enum PhoneVoiceChoice {
    static var current: YumiVoice { YumiVoice.stored() }

    static func label(_ voice: YumiVoice) -> String {
        switch voice {
        case .mac: loc("De l'iPhone")
        case .woman: loc("Femme")
        case .man: loc("Homme")
        }
    }
}

extension YumiVoice {
    var phoneLabel: String { PhoneVoiceChoice.label(self) }
}
