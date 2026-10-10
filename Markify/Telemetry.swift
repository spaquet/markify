import Foundation
import Sentry

/// The crash and performance reporting program. It is on by default; the onboarding sheet asks first-time users to
/// join, and Settings › Privacy turns it on or off at any time. Turning it off closes the Sentry client, so nothing
/// is sent for the rest of the session and on later launches.
@MainActor enum Telemetry {
    static let enabledKey = "telemetryEnabled"
    static let onboardedKey = "telemetryOnboarded"

    /// Whether the user is enrolled. Unset means enrolled: the program is on by default.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Whether the onboarding sheet has been answered. Set on the first answer, so it appears once per install.
    static var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: onboardedKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardedKey) }
    }

    /// Tests launch the app as their host: they report nothing and show no onboarding sheet.
    static var isUnderTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Whether the onboarding sheet should appear now.
    static var needsOnboarding: Bool { !hasOnboarded && !isUnderTest }

    /// Starts Sentry when the user is enrolled. The DSN comes from the SENTRY_DSN build setting
    /// (Config/Sentry.xcconfig); builds without one report nothing.
    static func startIfEnabled() {
        guard isEnabled, !isUnderTest,
              let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String, !dsn.isEmpty else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            #if DEBUG
            options.environment = "development"
            #else
            options.environment = "production"
            #endif
            // No IP address or other personal data.
            options.sendDefaultPii = false
            options.tracesSampleRate = 0.1
            options.configureProfiling = {
                $0.sessionSampleRate = 0.1
                $0.lifecycle = .trace
            }
        }
    }

    /// Enrolls or withdraws the user. Withdrawing closes the client at once; enrolling starts it again.
    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if enabled {
            if !SentrySDK.isEnabled { startIfEnabled() }
        } else {
            SentrySDK.close()
        }
    }
}
