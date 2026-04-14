//
//  HDRMetalOverlay.swift
//  HDRCore (isolated from BrightIntosh)
//
//  Extracted from BrightIntosh's `UI/Overlay.swift`. This is the `MTKView`
//  subclass that actually renders HDR content (a clear color with
//  components > 1.0) — which is what tricks macOS into putting the display
//  into extended-dynamic-range mode.
//
//  It has no dependency on BrightIntosh's UI, settings, or auth code.
//

import Cocoa
import MetalKit

/// Renders a 1×1 pixel EDR clear color whose component values exceed 1.0,
/// which signals macOS that HDR content is on screen.
public final class HDRMetalOverlay: MTKView, MTKViewDelegate {

    private let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
    private var commandQueue: MTLCommandQueue?

    public init(frame: CGRect, multiplyCompositing: Bool = false) {
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())

        guard let device else {
            fatalError("HDRMetalOverlay: no Metal device")
        }

        autoResizeDrawable = false
        drawableSize = CGSize(width: 1, height: 1)

        commandQueue = device.makeCommandQueue()
        if commandQueue == nil {
            fatalError("HDRMetalOverlay: could not create Metal command queue")
        }

        delegate = self
        colorPixelFormat = .rgba16Float
        colorspace = colorSpace
        clearColor = MTLClearColorMake(1.0, 1.0, 1.0, 1.0)
        preferredFramesPerSecond = 5

        if let layer = self.layer as? CAMetalLayer {
            layer.wantsExtendedDynamicRangeContent = true
            layer.isOpaque = false
            layer.pixelFormat = .rgba16Float
            if multiplyCompositing {
                layer.compositingFilter = "multiply"
            }
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Recomputes the clear-color so that it pushes past 1.0 based on the
    /// screen's maximum EDR head-room.
    public func screenUpdate(screen: NSScreen) {
        let maxEdrValue = screen.maximumExtendedDynamicRangeColorComponentValue
        let maxRenderedEdrValue = screen.maximumReferenceExtendedDynamicRangeColorComponentValue
        let factor = max(maxEdrValue / max(maxRenderedEdrValue, 1.0) - 1.0, 1.0)
        clearColor = MTLClearColorMake(factor, factor, factor, 1.0)
    }

    public func setMaxFrameRate(screen: NSScreen) {
        preferredFramesPerSecond = screen.maximumFramesPerSecond
    }

    /// Alternative clear-color setter that maps a normalized `[1.0, 1.6]`
    /// brightness value linearly across the display's EDR headroom.
    public func setHDRBrightness(colorValue: Double, screen: NSScreen) {
        let maxEdrValue = screen.maximumExtendedDynamicRangeColorComponentValue
        let percentage = (colorValue - 1.0) / 0.6
        let newColor = ((maxEdrValue - 1.0) * percentage) + 1.0
        clearColor = MTLClearColorMake(newColor, newColor, newColor, 1.0)
    }

    // MARK: - MTKViewDelegate

    public func draw(in view: MTKView) {
        guard let commandQueue = commandQueue,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        renderEncoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
