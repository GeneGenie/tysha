import SwiftUI

@main
struct BreathOSApp: App {
    /// Captured as early as app code runs. The in-app splash tops up the system
    /// launch screen so the total splash time is `RootView.splashTargetSec`.
    static let appStart = Date()

    init() { _ = Self.appStart } // force evaluation at launch

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    /// Total splash duration (system launch screen + in-app splash), seconds.
    static let splashTargetSec: TimeInterval = 2.0

    @State private var settings = BreathSettings.load()
    @State private var showSession = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            SettingsView(settings: $settings) {
                settings.save()
                showSession = true
            }
            .fullScreenCover(isPresented: $showSession) {
                SessionView(settings: settings) { showSession = false }
            }
            // Persist whenever a setting changes so config survives a quit without "Начать".
            .onChange(of: settings) { _, newValue in
                newValue.save()
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            // Hold the splash only for whatever is left of the 2s budget —
            // if startup already took longer, dismiss right away.
            let elapsed = Date().timeIntervalSince(BreathOSApp.appStart)
            let remaining = max(0, Self.splashTargetSec - elapsed)
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
            }
        }
    }
}

/// Mirrors the system launch screen (same full-bleed art), so the
/// system→in-app handoff is invisible and reads as one continuous splash.
struct SplashView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.005, green: 0.035, blue: 0.085) // matches art corners
                Image("LaunchSplash")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
        .ignoresSafeArea()
    }
}
