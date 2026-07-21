import SwiftUI

extension StockColorTheme {
    var risingColor: Color {
        switch self {
        case .greenUpRedDown: .green
        case .redUpGreenDown: .red
        }
    }

    var fallingColor: Color {
        switch self {
        case .greenUpRedDown: .red
        case .redUpGreenDown: .green
        }
    }

    func color(isRising: Bool) -> Color {
        isRising ? risingColor : fallingColor
    }
}
