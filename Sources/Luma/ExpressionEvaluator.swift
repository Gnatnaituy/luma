import Foundation

enum ExpressionError: LocalizedError {
    case unexpected(String)
    case divisionByZero

    var errorDescription: String? {
        switch self {
        case .unexpected(let value): L10n.text("无法解析：\(value)", "Cannot parse: \(value)")
        case .divisionByZero: L10n.text("不能除以零", "Cannot divide by zero")
        }
    }
}

struct ExpressionEvaluator {
    static func evaluate(_ expression: String) throws -> Double {
        var parser = Parser(expression.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/"))
        let value = try parser.parseExpression()
        parser.skipWhitespace()
        guard parser.isAtEnd else { throw ExpressionError.unexpected(String(parser.remaining)) }
        return value
    }

    static func display(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < Double(Int64.max) {
            return String(Int64(value))
        }
        return String(format: "%.10g", value)
    }

    private struct Parser {
        private let characters: [Character]
        private var index = 0

        init(_ input: String) {
            characters = Array(input)
        }

        var isAtEnd: Bool { index >= characters.count }
        var remaining: ArraySlice<Character> { characters[index...] }

        mutating func skipWhitespace() {
            while !isAtEnd, characters[index].isWhitespace { index += 1 }
        }

        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while true {
                skipWhitespace()
                if consume("+") { value += try parseTerm() }
                else if consume("-") { value -= try parseTerm() }
                else { return value }
            }
        }

        mutating func parseTerm() throws -> Double {
            var value = try parsePower()
            while true {
                skipWhitespace()
                if consume("*") { value *= try parsePower() }
                else if consume("/") {
                    let divisor = try parsePower()
                    guard divisor != 0 else { throw ExpressionError.divisionByZero }
                    value /= divisor
                } else if consume("%") {
                    let divisor = try parsePower()
                    guard divisor != 0 else { throw ExpressionError.divisionByZero }
                    value.formTruncatingRemainder(dividingBy: divisor)
                } else { return value }
            }
        }

        mutating func parsePower() throws -> Double {
            var value = try parseUnary()
            skipWhitespace()
            if consume("^") { value = pow(value, try parsePower()) }
            return value
        }

        mutating func parseUnary() throws -> Double {
            skipWhitespace()
            if consume("+") { return try parseUnary() }
            if consume("-") { return -(try parseUnary()) }
            return try parsePrimary()
        }

        mutating func parsePrimary() throws -> Double {
            skipWhitespace()
            if consume("(") {
                let value = try parseExpression()
                skipWhitespace()
                guard consume(")") else {
                    throw ExpressionError.unexpected(L10n.text("缺少右括号", "Missing closing parenthesis"))
                }
                return value
            }

            let name = parseName()
            if !name.isEmpty {
                if name == "pi" { return .pi }
                if name == "e" { return M_E }
                skipWhitespace()
                guard consume("(") else { throw ExpressionError.unexpected(name) }
                let argument = try parseExpression()
                guard consume(")") else {
                    throw ExpressionError.unexpected(L10n.text("缺少右括号", "Missing closing parenthesis"))
                }
                switch name {
                case "sqrt": return sqrt(argument)
                case "sin": return sin(argument)
                case "cos": return cos(argument)
                case "tan": return tan(argument)
                case "abs": return abs(argument)
                case "log": return log10(argument)
                case "ln": return log(argument)
                default: throw ExpressionError.unexpected(name)
                }
            }

            let number = parseNumber()
            guard let value = Double(number), !number.isEmpty else {
                throw ExpressionError.unexpected(
                    isAtEnd ? L10n.text("表达式不完整", "Incomplete expression") : String(characters[index])
                )
            }
            return value
        }

        mutating func parseName() -> String {
            skipWhitespace()
            let start = index
            while !isAtEnd, characters[index].isLetter { index += 1 }
            return String(characters[start..<index]).lowercased()
        }

        mutating func parseNumber() -> String {
            skipWhitespace()
            let start = index
            var hasDot = false
            while !isAtEnd {
                let character = characters[index]
                if character.isNumber { index += 1 }
                else if character == ".", !hasDot { hasDot = true; index += 1 }
                else { break }
            }
            return String(characters[start..<index])
        }

        mutating func consume(_ character: Character) -> Bool {
            skipWhitespace()
            guard !isAtEnd, characters[index] == character else { return false }
            index += 1
            return true
        }
    }
}
