import Foundation

extension String {
    /// The trimmed text, or nil when nothing but whitespace is left.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
