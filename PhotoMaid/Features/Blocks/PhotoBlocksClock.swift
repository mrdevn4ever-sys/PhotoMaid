import QuartzCore
import Foundation

/// Exactly one display link; a weak target prevents a retained game after navigation.
@MainActor final class PhotoBlocksClock {
    private var link: CADisplayLink?
    private var target: Target?
    private var last: CFTimeInterval?
    private var tick: (@MainActor (Double) -> Void)?

    func start(tick: @escaping @MainActor (Double) -> Void) {
        self.tick = tick
        guard link == nil else { return }
        last = nil
        let target = Target(); target.owner = self; self.target = target
        let link = CADisplayLink(target: target, selector: #selector(Target.frame(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        self.link = link; link.add(to: .main, forMode: .common)
    }
    func stop() { link?.invalidate(); link = nil; target = nil; tick = nil; last = nil }
    private func frame(_ link: CADisplayLink) {
        defer { if self.link != nil { last = link.timestamp } }
        guard let last else { return }
        tick?(min(0.05, max(0, link.timestamp - last)))
    }
    @MainActor private final class Target: NSObject {
        weak var owner: PhotoBlocksClock?
        @objc func frame(_ link: CADisplayLink) {
            guard let owner else { link.invalidate(); return }
            owner.frame(link)
        }
    }
}
