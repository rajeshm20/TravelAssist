import Foundation

enum JailbreakDetector {
    static func isJailbroken(fileManager: FileManager = .default) -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        if hasSuspiciousFiles(fileManager: fileManager) {
            return true
        }
        if canWriteOutsideSandbox(fileManager: fileManager) {
            return true
        }
        if hasInjectedDynamicLibraries() {
            return true
        }
        return false
        #endif
    }

    private static func hasSuspiciousFiles(fileManager: FileManager) -> Bool {
        let paths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt"
        ]
        return paths.contains { fileManager.fileExists(atPath: $0) }
    }

    private static func canWriteOutsideSandbox(fileManager: FileManager) -> Bool {
        let testPath = "/private/\(UUID().uuidString)"
        let data = Data("jailbreak-check".utf8)
        do {
            try data.write(to: URL(fileURLWithPath: testPath), options: [.atomic])
            try fileManager.removeItem(atPath: testPath)
            return true
        } catch {
            return false
        }
    }

    private static func hasInjectedDynamicLibraries() -> Bool {
        let suspiciousKeys = [
            "DYLD_INSERT_LIBRARIES",
            "DYLD_LIBRARY_PATH",
            "DYLD_FRAMEWORK_PATH"
        ]
        let environment = ProcessInfo.processInfo.environment
        return suspiciousKeys.contains { environment[$0] != nil }
    }
}

