import AppKit
import QuartzCore

/// CAMetalLayer that mpv renders into (vo=gpu-next → Vulkan → MoltenVK → Metal).
/// Workarounds borrowed from MPVKit's demo (see mpv-player/mpv#13651).
final class MetalLayer: CAMetalLayer {
    // MoltenVK sometimes sets drawableSize to 1x1 to force-complete a presentation, which causes flicker.
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }

    // EDR (HDR) mode only activates when this is set on the main thread.
    override var wantsExtendedDynamicRangeContent: Bool {
        get { super.wantsExtendedDynamicRangeContent }
        set {
            if Thread.isMainThread {
                super.wantsExtendedDynamicRangeContent = newValue
            } else {
                // async, never sync: a background thread must not wait on main (see MPVCore).
                DispatchQueue.main.async { super.wantsExtendedDynamicRangeContent = newValue }
            }
        }
    }
}
