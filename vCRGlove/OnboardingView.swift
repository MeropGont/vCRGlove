//
//  OnboardingView.swift
//  vCRGlove
//
//  First-launch tutorial that explains every main feature in large,
//  easy-to-read steps for users who are not familiar with smartphones.
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var pageIndex = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Willkommen bei vCRGlove",
            bodyText: "Diese App hilft Ihnen, Ihre Bewegungen und Ihr Befinden rund um die vCR-Therapie zu dokumentieren. Alles geschieht Schritt für Schritt.",
            systemImage: "hand.wave.fill"
        ),
        OnboardingPage(
            title: "1. Tägliches Journal",
            bodyText: "Jeden Tag können Sie einchecken: Stimmung, Symptome, Medikamente und Notizen. Das Journal hilft Ihnen und Ihrem Arzt, Verläufe zu erkennen.",
            systemImage: "book.fill"
        ),
        OnboardingPage(
            title: "2. vCR-Sitzungen",
            bodyText: "Unter „vCR“ starten Sie Ihre Vibrations-Therapie. Die App leitet Sie durch die Sitzung und merkt sich, wann Sie eine Behandlung hatten.",
            systemImage: "waveform.path.ecg"
        ),
        OnboardingPage(
            title: "3. Bewegungstests",
            bodyText: "Unter „Movement“ finden Sie geführte Tests: Finger-Tippen, Hand öffnen/schließen und Unterarm drehen. Jeder Test dauert 30 Sekunden. Führen Sie die Bewegung so schnell und so weit wie möglich aus.",
            systemImage: "hand.tap.fill"
        ),
        OnboardingPage(
            title: "So funktioniert die Aufnahme",
            bodyText: "Wählen Sie den passenden Kontext (z. B. vor oder nach der vCR-Sitzung), drücken Sie Start und folgen Sie der Anleitung. Für manche Tests wird die Kamera verwendet, für andere die Apple Watch.",
            systemImage: "record.circle.fill"
        ),
        OnboardingPage(
            title: "4. Kalender",
            bodyText: "Im Kalender sehen Sie auf einen Blick, an welchen Tagen Sie ein Journal geschrieben oder einen Bewegungstest gemacht haben. Ein dunkelgrüner Kreis bedeutet: An diesem Tag gibt es Messdaten.",
            systemImage: "calendar"
        ),
        OnboardingPage(
            title: "5. Einstellungen & Export",
            bodyText: "Unter „Settings“ tragen Sie Ihre Patienten-ID ein und können Ihre Daten sicher exportieren. Ihre Daten werden pseudonymisiert gespeichert.",
            systemImage: "gearshape.fill"
        ),
        OnboardingPage(
            title: "Bereit?",
            bodyText: "Drücken Sie auf „App starten“. Sie können dieses Tutorial nicht erneut ansehen, aber alle Funktionen finden Sie jederzeit in den einzelnen Tabs.",
            systemImage: "checkmark.circle.fill"
        )
    ]

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: pages[pageIndex].systemImage)
                    .font(.system(size: 88))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 20) {
                    Text(L10n(pages[pageIndex].title))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)

                    Text(L10n(pages[pageIndex].bodyText))
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                }

                Spacer()

                VStack(spacing: 16) {
                    PageIndicator(count: pages.count, currentIndex: pageIndex)

                    Button {
                        if pageIndex < pages.count - 1 {
                            withAnimation { pageIndex += 1 }
                        } else {
                            hasSeenOnboarding = true
                        }
                    } label: {
                        Text(L10n(pageIndex < pages.count - 1 ? "Weiter" : "App starten"))
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 32)

                    if pageIndex < pages.count - 1 {
                        Button {
                            hasSeenOnboarding = true
                        } label: {
                            Text(L10n("Überspringen"))
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.bottom, 32)
            }
        }
    }
}

private struct OnboardingPage {
    let title: String
    let bodyText: String
    let systemImage: String
}

private struct PageIndicator: View {
    let count: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)
            }
        }
    }
}

#Preview {
    OnboardingView()
}
