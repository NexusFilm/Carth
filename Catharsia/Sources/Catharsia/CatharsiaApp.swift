import SwiftUI

@main
struct CatharsiaApp: App {
    @UIApplicationDelegateAdaptor(CatharsiaAppDelegate.self) private var appDelegate
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(session)
                .tint(CatharsiaStyle.violet)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    Task { await session.handleOpenURL(url) }
                }
        }
    }
}
