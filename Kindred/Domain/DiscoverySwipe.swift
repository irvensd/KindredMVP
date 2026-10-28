import Foundation

/// One gesture's intent. Once scrolling wins, that touch cannot become a profile action.
struct DiscoverySwipe {
    enum Axis { case undecided, horizontal, vertical }
    enum Action { case next, interested }
    private(set) var axis: Axis = .undecided
    private(set) var translation: CGFloat = 0
    private var verticalTranslation: CGFloat = 0
    private(set) var didReachThreshold = false

    static func threshold(width: CGFloat) -> CGFloat { min(104, max(80, width * 0.25)) }

    mutating func update(_ delta: CGSize, width: CGFloat, isLiked: Bool) {
        let x = abs(delta.width), y = abs(delta.height)
        if axis == .undecided {
            guard max(x, y) >= 14 else { return }
            if x > y * 1.35 { axis = .horizontal }
            else if y > x * 1.35 || max(x, y) >= 28 { axis = .vertical }
        }
        // A horizontal start that turns into a scroll also cancels permanently.
        if axis == .horizontal && y > x * 1.35 { axis = .vertical }
        translation = axis == .horizontal ? delta.width : 0
        verticalTranslation = axis == .horizontal ? delta.height : 0
        if isReady(width: width, isLiked: isLiked) { didReachThreshold = true }
    }

    func isReady(width: CGFloat, isLiked: Bool) -> Bool {
        axis == .horizontal && abs(translation) > abs(verticalTranslation) * 1.35
            && abs(translation) >= Self.threshold(width: width)
            && (translation < 0 || !isLiked)
    }

    func action(at delta: CGSize, predicted: CGSize, velocity: CGSize, width: CGFloat, isLiked: Bool) -> Action? {
        guard axis == .horizontal, abs(delta.width) > abs(delta.height) * 1.35 else { return nil }
        let distance = abs(delta.width), threshold = Self.threshold(width: width)
        // A short flick needs substantial travel, speed, and agreement about direction.
        // Prediction alone must never turn a small nudge or reversal into a like/pass.
        let flick = distance >= threshold * 0.65 && abs(velocity.width) >= 500
            && delta.width * velocity.width > 0
            && delta.width * predicted.width > 0 && abs(predicted.width) >= threshold * 1.5
        guard distance >= threshold || flick else { return nil }
        if delta.width < 0 { return .next }
        return isLiked ? nil : .interested
    }

    func offset(width: CGFloat) -> CGFloat {
        let distance = abs(translation)
        let limit = min(88, max(60, width * 0.24))
        let resisted = limit * distance / (distance + Self.threshold(width: width))
        return translation < 0 ? -resisted : resisted
    }
}
