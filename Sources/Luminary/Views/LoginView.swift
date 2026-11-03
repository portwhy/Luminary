import AppKit
import SwiftUI

struct LoginView: View {
    @Environment(SessionManager.self) private var session

    @State private var server = SessionManager.lastServerInput
    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case server, username, password }

    private var canSubmit: Bool {
        !isWorking
            && !server.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 14) {
                LuminaryLogo(size: 92)
                VStack(spacing: 4) {
                    Text("Luminary")
                        .font(.system(size: 30, weight: .semibold))
                    Text("Sign in to your Jellyfin server")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 10) {
                LoginField(focused: focus == .server) {
                    TextField("Server", text: $server, prompt: Text("192.168.1.10:8096"))
                        .focused($focus, equals: .server)
                        .onSubmit { focus = .username }
                }
                LoginField(focused: focus == .username) {
                    TextField("Username", text: $username, prompt: Text("Username"))
                        .textContentType(.username)
                        .focused($focus, equals: .username)
                        .onSubmit { focus = .password }
                }
                LoginField(focused: focus == .password) {
                    SecureField("Password", text: $password, prompt: Text("Password"))
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .onSubmit(signIn)
                }
            }
            .textFieldStyle(.plain)
            .disabled(isWorking)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: signIn) {
                HStack(spacing: 8) {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text(isWorking ? "Connecting…" : "Sign In")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(.black.opacity(canSubmit || isWorking ? 0.9 : 0.4))
                .background(.white.opacity(canSubmit || isWorking ? 0.92 : 0.3), in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)
        }
        .padding(34)
        .frame(width: 400)
        .loginGlassCard()
        // Just under the box. Hung off its bottom edge so the box itself stays centered in the window.
        .overlay(alignment: .bottom) {
            SupportLink()
                .alignmentGuide(.bottom) { $0[.top] - 14 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LoginWindowGlass())
        .onAppear { focus = server.isEmpty ? .server : .username }
    }

    private func signIn() {
        guard canSubmit else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await session.signIn(server: server, username: username, password: password)
            } catch is CancellationError {
                // view went away
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Pieces

/// A text field's rounded, softly lit container.
private struct LoginField<Content: View>: View {
    let focused: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(focused ? 0.45 : 0.12), lineWidth: focused ? 1.5 : 1)
            )
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

private extension View {
    /// Liquid Glass card on macOS 26, a blurred material before that.
    @ViewBuilder
    func loginGlassCard() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
    }
}

/// The app icon, drawn in SwiftUI so it looks the same however the app is launched.
struct LuminaryLogo: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.20, green: 0.16, blue: 0.48), Color(red: 0.06, green: 0.30, blue: 0.62)],
                    startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(RadialGradient(
                    colors: [Color(red: 0.65, green: 0.85, blue: 1).opacity(0.85), Color(red: 0.35, green: 0.6, blue: 1).opacity(0)],
                    center: .center, startRadius: 0, endRadius: size * 0.52))
            PlayTriangle()
                .fill(.white)
                .shadow(color: Color(red: 0.3, green: 0.5, blue: 1).opacity(0.6), radius: size * 0.03, y: size * 0.01)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: size * 0.12, y: size * 0.05)
    }
}

/// Rounded play triangle whose centroid sits on the center of its square (the way it reads as centered).
private struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        let a = point(0.382, 0.704), b = point(0.382, 0.296), c = point(0.734, 0.5)
        let radius = rect.width * 0.055
        var path = Path()
        path.move(to: CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2))
        path.addArc(tangent1End: a, tangent2End: b, radius: radius)
        path.addArc(tangent1End: b, tangent2End: c, radius: radius)
        path.addArc(tangent1End: c, tangent2End: a, radius: radius)
        path.closeSubpath()
        return path
    }
}

/// Makes the sign-in window itself see-through Liquid Glass (always, whatever the library's glass setting is).
/// When the login goes away the window returns to whatever the library wants.
private struct LoginWindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
    static func dismantleNSView(_ nsView: Probe, coordinator: ()) { nsView.restore() }

    final class Probe: NSView {
        private var glass: NSView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, glass == nil, let frameView = window.contentView?.superview else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            let view: NSView
            if #available(macOS 26.0, *) {
                view = NSGlassEffectView()
            } else {
                let effect = NSVisualEffectView()
                effect.material = .underWindowBackground
                effect.blendingMode = .behindWindow
                effect.state = .active
                view = effect
            }
            view.frame = frameView.bounds
            view.autoresizingMask = [.width, .height]
            frameView.addSubview(view, positioned: .below, relativeTo: window.contentView)
            glass = view
        }

        func restore() {
            glass?.removeFromSuperview()
            glass = nil
            guard let window else { return }
            let glassOn = MainActor.assumeIsolated { AppTheme.shared.glass }
            window.isOpaque = !glassOn
            window.backgroundColor = glassOn ? .clear : AppTheme.solidNS
        }
    }
}

/// Quiet "Support Luminary" link under the sign-in box, with the same soft hover highlight as the sidebar buttons.
private struct SupportLink: View {
    @Environment(\.openURL) private var openURL
    @State private var isHovering = false

    var body: some View {
        Button {
            openURL(Links.support)
        } label: {
            Label("Support Luminary", systemImage: "heart.fill")
                .font(.callout)
                .foregroundStyle(isHovering ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(isHovering ? 0.08 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
