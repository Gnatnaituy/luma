import SwiftUI

enum LumaMotion {
    static let press = Animation.easeOut(duration: 0.14)
    static let quick = Animation.easeInOut(duration: 0.18)
    static let standard = Animation.easeInOut(duration: 0.24)

    static let contentTransition = AnyTransition.opacity.combined(with: .offset(y: 8))
    static let rowTransition = AnyTransition.opacity.combined(with: .scale(scale: 0.98))
}

extension View {
    func lumaContentTransition() -> some View {
        transition(LumaMotion.contentTransition)
    }
}
