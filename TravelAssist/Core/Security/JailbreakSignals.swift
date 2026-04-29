//
//  JailbreakSignals.swift
//  TravelAssist
//
//  Created by Rajesh Mani on 27/04/26.
//
import Foundation

struct JailbreakSignals {
    var suspiciousFiles = false
    var sandboxEscape = false
    var injectedLibs = false
    var dyldTampering = false
    var debugger = false
}

enum SecurityLevel {
    case safe
    case suspicious
    case highRisk
}

final class BankGradeJailbreakDetector {

    static func evaluate() -> SecurityLevel {

        #if targetEnvironment(simulator)
        return .safe
        #endif

        var score = 0
        let signals = collectSignals()

        if signals.suspiciousFiles { score += 2 }
        if signals.sandboxEscape { score += 3 }
        if signals.injectedLibs { score += 3 }
        if signals.dyldTampering { score += 3 }
        if signals.debugger { score += 1 }

        switch score {
        case 0...2: return .safe
        case 3...5: return .suspicious
        default: return .highRisk
        }
    }

    private static func collectSignals() -> JailbreakSignals {
        return JailbreakSignals(
            suspiciousFiles: JailbreakDetector.hasSuspiciousFiles(),
            sandboxEscape: JailbreakDetector.canWriteOutsideSandbox(),
            injectedLibs: JailbreakDetector.hasInjectedDynamicLibraries(),
            dyldTampering: JailbreakDetector.hasDyldInjection(),
            debugger: JailbreakDetector.isDebuggerAttached()
        )
    }
}
