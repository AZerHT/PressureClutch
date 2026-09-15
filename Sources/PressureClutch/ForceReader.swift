import CMultitouch
import Foundation

/// Reads how hard the trackpad is being pressed, finger by finger, from MultitouchSupport's contact frames.
///
/// Frames arrive on the framework's own thread, about a hundred times a second while a finger touches the
/// trackpad. Only the strongest finger counts: when one finger holds the click and another moves, the clicking one
/// is the one pressing.
final class ForceReader {
    static let shared = ForceReader()

    private let lock = NSLock()
    private var latestForce: Float = 0
    /// The device list must stay alive for the callbacks to keep coming.
    private var devices: CFArray?

    var force: Float {
        lock.lock()
        defer { lock.unlock() }
        return latestForce
    }

    /// False when no trackpad was found.
    func start() -> Bool {
        guard devices == nil else { return true }
        guard let list = MTDeviceCreateList()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else { return false }
        devices = list
        for index in 0..<CFArrayGetCount(list) {
            guard let pointer = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: pointer)
            MTRegisterContactFrameCallback(device, contactFrame)
            MTDeviceStart(device, 0)
        }
        return true
    }

    fileprivate func record(_ force: Float) {
        lock.lock()
        latestForce = force
        lock.unlock()
    }
}

private let contactFrame: MTContactCallback = { _, touches, count, _, _ in
    var strongest: Float = 0
    if let touches {
        for index in 0..<Int(count) {
            strongest = max(strongest, touches[index].zPressure)
        }
    }
    ForceReader.shared.record(strongest)
    return 0
}
