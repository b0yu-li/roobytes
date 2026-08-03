import Foundation

/// Colon-command (`:…`) catalog for Roobytes’s simple ex mode.
public enum VimExCommand: String, CaseIterable, Sendable {
    case write
    case quit
    case pin
    case discard
    case help
    case tips
    case complete
    case daily
    case folddone

    /// Canonical name shown in completions.
    public var canonical: String {
        switch self {
        case .write: return "w"
        case .quit: return "q"
        case .pin: return "pin"
        case .discard: return "e!"
        case .help: return "h"
        case .tips: return "tips"
        case .complete: return "complete"
        case .daily: return "daily"
        case .folddone: return "folddone"
        }
    }

    /// Accepted spellings (including bangs / long forms).
    public var aliases: [String] {
        switch self {
        case .write: return ["w", "w!", "write"]
        case .quit: return ["q", "quit"]
        case .pin: return ["pin"]
        case .discard: return ["e!", "discard", "revert"]
        case .help: return ["h", "help"]
        case .tips: return ["tips", "tip"]
        case .complete: return ["complete", "cmp", "autocomplete"]
        case .daily: return ["daily", "today"]
        case .folddone: return ["folddone", "fd"]
        }
    }

    public var successMessage: String? {
        switch self {
        case .write: return "Written"
        case .quit: return nil
        case .pin: return nil // set by host from pin state
        case .discard: return "Discarded"
        case .help: return nil
        case .tips: return nil
        case .complete: return nil // set by host from toggle state
        case .daily: return nil // set by host
        case .folddone: return nil // set by host from fold count
        }
    }

    /// Exact resolve of a typed command body (no leading `:`).
    public static func resolve(_ raw: String) -> VimExCommand? {
        let cmd = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cmd.isEmpty else { return nil }
        for item in allCases where item.aliases.contains(cmd) {
            return item
        }
        return nil
    }

    /// Best autocomplete candidate for a typed prefix (no leading `:`).
    /// Prefers the shortest alias that still uniquely identifies a command family.
    public static func completion(forPrefix typed: String) -> String? {
        let prefix = typed.lowercased()
        guard !prefix.isEmpty else { return nil }

        // Already an exact alias — nothing to complete.
        if resolve(prefix) != nil { return nil }

        let hits = allCases.flatMap(\.aliases).filter { $0.hasPrefix(prefix) }
        guard !hits.isEmpty else { return nil }

        // Prefer shortest alias among hits (e.g. `w` over `write` when uniquely implied).
        let best = hits.min(by: { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return lhs < rhs
        })
        return best
    }

    /// Ghost suffix after `typed` when a completion exists (`pin` for typed `p` → `in`).
    public static func ghostSuffix(forPrefix typed: String) -> String? {
        guard let full = completion(forPrefix: typed), full.count > typed.count else { return nil }
        return String(full.dropFirst(typed.count))
    }
}
