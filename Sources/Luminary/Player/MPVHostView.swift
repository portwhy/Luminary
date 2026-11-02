import AppKit
import SwiftUI

/// SwiftUI wrapper for the Metal-backed view mpv renders into.
struct MPVVideoView: NSViewRepresentable {
    let controller: PlaybackController

    func makeNSView(context: Context) -> MPVHostView {
        let view = MPVHostView(frame: .zero)
        view.controller = controller
        return view
    }

    func updateNSView(_ nsView: MPVHostView, context: Context) {}

    static func dismantleNSView(_ nsView: MPVHostView, coordinator: ()) {
        nsView.removeEventMonitor()
    }
}

/// Layer-hosting NSView whose backing layer is mpv's CAMetalLayer. Also owns the window-scoped
/// keyboard / trackpad monitor, because SwiftUI has no scroll-wheel events and its focus model
/// makes global player shortcuts unreliable.
final class MPVHostView: NSView {
    weak var controller: PlaybackController?
    private var eventMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []

    /// mpv's render target. A child layer whose frame we set explicitly on every layout (like the MPVKit demo),
    /// rather than the view's own backing layer: that is what lets mpv follow window size changes live.
    private let metal: MetalLayer = {
        let layer = MetalLayer()
        layer.framebufferOnly = true
        layer.backgroundColor = NSColor.black.cgColor
        return layer
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(metal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var metalLayer: MetalLayer? { metal }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            removeEventMonitor()
            return
        }
        updateDrawableSize()
        controller?.hostView = self
        if let metalLayer {
            controller?.player.attach(layer: metalLayer)
        }
        installEventMonitor()
        observeFullScreen()
        // Player windows must not come back on the next launch (macOS restored them, even in full screen).
        window?.isRestorable = false
    }

    private func observeFullScreen() {
        guard windowObservers.isEmpty, let window else { return }
        let names: [Notification.Name] = [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification]
        windowObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.controller?.updateFullScreenState() }
            }
        }
        // SwiftUI Menus are NSMenus: keep the controls up for as long as one is open.
        windowObservers.append(NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window?.isKeyWindow == true else { return }
                self.controller?.setMenuOpen(true)
            }
        })
        windowObservers.append(NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller?.setMenuOpen(false) }
        })
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    /// mpv renders into a drawable of one fixed size (16:9, as many pixels as the biggest screen is wide, capped at
    /// 4K) for the whole life of the window. Core Animation scales that layer to fit the view, centred. libmpv is
    /// never told about window resizing (we own the Metal layer, it doesn't), and when it guessed wrong the
    /// picture stayed stretched or in a corner for seconds; with a fixed size there is nothing for it to miss, and
    /// resizing and full screen are just a layer transform, so they are instant.
    private lazy var renderPixelSize: CGSize = {
        let widest = NSScreen.screens.map { $0.frame.width * $0.backingScaleFactor }.max() ?? 2560
        let width = min(max(widest, 1920), 3840).rounded()
        return CGSize(width: width, height: (width * 9 / 16).rounded())
    }()

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let points = CGSize(width: renderPixelSize.width / scale, height: renderPixelSize.height / scale)
        let fit = min(bounds.width / points.width, bounds.height / points.height)
        // No implicit animation: the layer must be exactly in place on every frame of a live resize.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metal.bounds = CGRect(origin: .zero, size: points)
        metal.contentsScale = scale
        metal.drawableSize = renderPixelSize
        metal.position = CGPoint(x: bounds.midX, y: bounds.midY)
        metal.transform = CATransform3DMakeScale(fit, fit, 1)
        CATransaction.commit()
    }

    // MARK: Input

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.window, let controller = self.controller else { return false }
                switch event.type {
                case .keyDown: return controller.handleKey(event)
                case .scrollWheel: return controller.handleScroll(event)
                default: return false
                }
            }
            return handled ? nil : event
        }
    }

    func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers = []
    }
}
