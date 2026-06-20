import NexusDomain
import SwiftUI

/// One shared semantic status vocabulary for every Nexus status indicator (Provider
/// Health, Host Validation, Workspace Availability, Session state). Each domain status
/// enum maps into a tone below rather than choosing its own color/symbol, so a status
/// pill reads identically across the app regardless of which domain concept it reports.
enum NexusStatusTone {
    case healthy
    case warning
    case critical
    case blocked
    case unknown

    var symbolName: String {
        switch self {
        case .healthy:
            "checkmark.circle"
        case .warning:
            "wifi.exclamationmark"
        case .critical:
            "exclamationmark.triangle"
        case .blocked:
            "pause.circle"
        case .unknown:
            "clock"
        }
    }
}

#if os(macOS)
    extension NexusStatusTone {
        var color: Color {
            switch self {
            case .healthy:
                NexusMacTheme.teal
            case .warning:
                NexusMacTheme.gold
            case .critical:
                NexusMacTheme.coral
            case .blocked:
                NexusMacTheme.subtleText
            case .unknown:
                NexusMacTheme.mutedText
            }
        }
    }

    extension ProviderHealthSummary.State {
        var tone: NexusStatusTone {
            switch self {
            case .available:
                .healthy
            case .unavailable, .blocked:
                .warning
            case .misconfigured:
                .critical
            case .notChecked:
                .unknown
            }
        }
    }

    extension Session.State {
        var tone: NexusStatusTone {
            switch self {
            case .ready:
                .healthy
            case .interrupted:
                .warning
            case .exited, .failed:
                .critical
            }
        }
    }

    extension HostValidationSnapshot.State? {
        var tone: NexusStatusTone {
            switch self {
            case .available:
                .healthy
            case .unavailable:
                .warning
            case .broken:
                .critical
            case .notChecked, .none:
                .unknown
            }
        }
    }

    extension WorkspaceAvailabilitySnapshot.State {
        var tone: NexusStatusTone {
            switch self {
            case .available:
                .healthy
            case .unavailable:
                .warning
            case .broken:
                .critical
            case .blocked:
                .blocked
            }
        }
    }
#endif
