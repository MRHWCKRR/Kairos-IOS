import Foundation

enum KairosPlannerDecoding {
    static func message(for error: Error) -> String {
        let path: [CodingKey]
        let problem: String
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            path = context.codingPath + [key]; problem = "is missing"
        case DecodingError.typeMismatch(_, let context):
            path = context.codingPath; problem = "has an unsupported format"
        case DecodingError.valueNotFound(_, let context):
            path = context.codingPath; problem = "is empty"
        case DecodingError.dataCorrupted(let context):
            path = context.codingPath; problem = "could not be read"
        default:
            return "Could not read this planner. Retry loading, or review it on the web."
        }
        let field = path.reduce("") { value, key in
            if let index = key.intValue { return value + "[\(index)]" }
            return value + (value.isEmpty ? "" : ".") + key.stringValue
        }
        return "Could not read your planner: \(field.isEmpty ? "planner" : field) \(problem)."
    }
}
