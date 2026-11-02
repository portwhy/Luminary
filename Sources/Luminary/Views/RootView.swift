import SwiftUI

struct RootView: View {
    @Environment(SessionManager.self) private var session

    var body: some View {
        Group {
            if ProcessInfo.processInfo.environment["LUMINARY_SHOW_LOGIN"] != nil {
                // Preview only (`open --env LUMINARY_SHOW_LOGIN=1 Luminary.app`): look at the sign-in screen without
                // signing out.
                LoginView()
            } else {
                content
            }
        }
        .task {
            if case .restoring = session.state {
                await session.restore()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch session.state {
            case .restoring:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                LoginView()
            case .signedIn(let authenticated):
                LibraryShellView(session: authenticated)
                    .id(authenticated.user.id)
            }
        }
    }
}
