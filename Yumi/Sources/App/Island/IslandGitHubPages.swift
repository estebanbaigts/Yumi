import SwiftUI

// The island's GitHub view in three pages, one seen at a time: ‹ title › and three dots,
// the arrow keys while the island is in front. Every page is laid out at once so the island
// keeps the height of the tallest (each list scrolls past its own limit); the others are
// faded out and slid a little aside.

struct GitHubPager: View {
    let module: ModuleSnapshot
    @AppStorage(GitHubPage.storageKey) private var stored = GitHubPage.activity.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var page: GitHubPage { GitHubPage(rawValue: stored) ?? .activity }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            ZStack(alignment: .topLeading) {
                ForEach(GitHubPage.allCases, id: \.self) { each in
                    content(each)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(each == page ? 1 : 0)
                        .offset(x: reduceMotion ? 0 : CGFloat(each.rawValue - page.rawValue) * 18)
                        .allowsHitTesting(each == page)
                        .accessibilityHidden(each != page)
                }
            }
        }
        .onAppear { GitHubPagerKeys.shown = true }
        .onDisappear { GitHubPagerKeys.shown = false }
        .onReceive(NotificationCenter.default.publisher(for: .githubPageStep)) { note in
            if let step = note.userInfo?["step"] as? Int { go(step) }
        }
    }

    private func go(_ step: Int) {
        let next = page.moved(by: step)
        guard next != page else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { stored = next.rawValue }
    }

    private var header: some View {
        HStack(spacing: 4) {
            arrow("chevron.left", label: loc("Page précédente"), enabled: page.hasPrevious) { go(-1) }
            Text(page.title)
                .font(IslandTheme.text(11.5, .semibold))
                .foregroundStyle(IslandTheme.fg)
                .contentTransition(.opacity)
            arrow("chevron.right", label: loc("Page suivante"), enabled: page.hasNext) { go(1) }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(GitHubPage.allCases, id: \.self) { each in
                    Circle()
                        .fill(each == page ? IslandTheme.fg : IslandTheme.faint)
                        .frame(width: 4, height: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(loc("Page \(page.rawValue + 1) sur \(GitHubPage.allCases.count)"))
        }
    }

    private func arrow(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(enabled ? IslandTheme.muted : IslandTheme.faint.opacity(0.5))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// The module with the page's lines in place of its own, for the common list.
    private func listing(_ rows: [ModuleRow]) -> ModuleSnapshot {
        var list = module
        list.rows = rows
        return list
    }

    @ViewBuilder private func content(_ each: GitHubPage) -> some View {
        if let key = each.rowsKey {
            let rows = module.pages[key] ?? []
            if rows.isEmpty {
                ActSub(text: each == .recent ? loc("Rien de poussé récemment.") : each == .pulls ? loc("Aucune pull request ouverte.") : loc("Aucun dépôt suivi."))
            } else {
                ModuleRowsList(module: listing(rows), lines: 3).padding(.leading, -7)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                IslandContributions(cell: 7, gap: 2)
                if let figures = GitHubFigures.parse(module.status) {
                    HStack(spacing: 12) {
                        GitHubFigure(symbol: "star.fill", value: figures.stars, label: loc("étoiles"))
                        GitHubFigure(symbol: "arrow.triangle.branch", value: figures.forks, label: loc("forks"))
                        GitHubFigure(symbol: "arrow.triangle.pull", value: figures.pulls, label: loc("pull requests ouvertes"))
                    }
                }
            }
        }
    }
}

/// Whether the pager is on screen, for the island's keyboard monitor.
@MainActor enum GitHubPagerKeys {
    static var shown = false

    /// ← and → turn the page while the island is in front, unless a text field has the keys.
    static func handle(keyCode: UInt16, plain: Bool) -> Bool {
        guard shown, plain, keyCode == 123 || keyCode == 124,
              !(NSApp.keyWindow?.firstResponder is NSText) else { return false }
        NotificationCenter.default.post(name: .githubPageStep, object: nil, userInfo: ["step": keyCode == 123 ? -1 : 1])
        return true
    }
}
