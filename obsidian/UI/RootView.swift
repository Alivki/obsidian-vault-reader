import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Prefs.appearance) private var appearance = Appearance.system.rawValue

    var body: some View {
        ZStack {
            Shad.background.ignoresSafeArea()
            if model.auth.token == nil {
                SignInView()
                    .transition(.opacity)
            } else {
                MainView()
                    .transition(.opacity)
            }
            ToastOverlay(center: model.toasts)
        }
        .animation(.easeInOut(duration: 0.25), value: model.auth.token == nil)
        .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        .tint(Shad.link)
        #if os(iOS)
        // Hide note content in the app switcher snapshot.
        .overlay {
            if scenePhase != .active, model.auth.token != nil {
                PrivacyCover().transition(.opacity)
            }
        }
        #else
        .frame(minWidth: 380, minHeight: 480)
        #endif
    }
}

private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Shad.background.ignoresSafeArea()
            Image(systemName: "book.closed")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Shad.mutedForeground)
        }
    }
}
