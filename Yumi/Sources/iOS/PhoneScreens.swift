import SwiftUI

// The screens reached from the menu or a card (step 11 of the redesign).

struct PhoneModulesView: View { let phone: Phone; var body: some View { Color.clear } }
struct PhoneAgentsView: View { let phone: Phone; var body: some View { Color.clear } }
struct PhoneAgendaView: View { let phone: Phone; var body: some View { Color.clear } }
struct PhoneWeatherView: View { let phone: Phone; var body: some View { Color.clear } }
struct PhoneWeatherBackdrop: View { let phone: Phone; var body: some View { Color.clear } }
struct PhoneLinkView: View { let phone: Phone; var body: some View { Color.clear } }

// MARK: - Weather

/// The weather as the Mac's island shows it: the same seven moods and their animated ground.
enum PhoneWeather {
    @MainActor static func ambiance(_ state: WeatherState) -> WeatherAmbiance? {
        guard case .ready(let report) = state else { return nil }
        return WeatherAmbiance.pick(symbol: WeatherSummary.symbol(for: state), status: "\(Int(report.temperature.rounded()))°")
    }

    static func degrees(_ report: WeatherReport) -> String { "\(Int(report.temperature.rounded()))°" }
}

/// The weather card of « Aujourd'hui »: its ambiance behind, Yumi in it.
struct PhoneWeatherTile: View {
    let phone: Phone

    var body: some View {
        let state = phone.today.weather
        let mood = PhoneWeather.ambiance(state)
        HStack(spacing: u(12)) {
            PhoneMiniYumi(state: .idle).frame(width: u(40), height: u(40))
            VStack(alignment: .leading, spacing: u(2)) {
                Text(phone.today.placeName.isEmpty ? loc("Météo") : loc("Météo · \(phone.today.placeName)"))
                    .phoneEyebrow(mood?.color ?? PhoneTheme.listen)
                switch state {
                case .ready(let report):
                    HStack(alignment: .firstTextBaseline, spacing: u(8)) {
                        Text(PhoneWeather.degrees(report)).font(.system(size: u(24), weight: .bold)).monospacedDigit()
                        Text("\(mood?.name ?? "") · \(WeatherSummary.sky(report.code))")
                            .font(.system(size: u(12))).foregroundStyle(YumiRGB(hex: 0xD6D8E0).color).lineLimit(1)
                    }
                case .loading:
                    ProgressView().padding(.top, u(4))
                case .unavailable:
                    Text(loc("Je n'arrive pas à avoir la météo.")).font(.system(size: u(12.5))).foregroundStyle(PhoneTheme.gray)
                case .needsLocation:
                    Text(loc("Je ne sais pas encore où tu es.")).font(.system(size: u(12.5))).foregroundStyle(PhoneTheme.gray)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: u(52))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                PhoneTheme.ink
                if let mood { WeatherEffects(ambiance: mood).opacity(0.7).allowsHitTesting(false) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: u(20), style: .continuous))
    }
}
