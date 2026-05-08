import Foundation
import UIKit
import MachO
import Darwin

enum JailbreakDetector {
    
    static func isJailbroken(fileManager: FileManager = .default) -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        if skipDebugDevice() {
            return false
        }
        
        // Multi-layered detection approach
        return hasSuspiciousFiles(fileManager: fileManager) ||
               canWriteOutsideSandbox(fileManager: fileManager) ||
               hasInjectedDynamicLibraries() ||
               hasSuspiciousSymlinks(fileManager: fileManager) ||
               canOpenCydiaURL() ||
               hasSuspiciousSystemCalls()
        #endif
    }
    
    // MARK: - Detection Methods
    
    static func hasSuspiciousFiles(fileManager: FileManager = .default) -> Bool {
        let paths = [
            // Jailbreak tools
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Applications/checkra1n.app",
            "/Applications/Unc0ver.app",
            "/Applications/RockApp.app",
            "/Applications/blackra1n.app",
            
            // Jailbreak binaries and libraries
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/usr/lib/libsubstrate.dylib",
            "/usr/lib/substrate",
            "/usr/libexec/cydia",
            
            // Unix binaries (shouldn't exist on non-jailbroken devices)
            "/bin/bash",
            "/bin/sh",
            "/usr/sbin/sshd",
            "/usr/bin/ssh",
            "/usr/libexec/sftp-server",
            
            // Package managers
            "/etc/apt",
            "/etc/apt/sources.list.d",
            "/private/var/lib/apt",
            "/private/var/lib/cydia",
            "/var/cache/apt",
            "/var/lib/dpkg",
            
            // Common jailbreak artifacts
            "/private/var/stash",
            "/private/var/mobile/Library/SBSettings/Themes",
            "/Library/MobileSubstrate/DynamicLibraries/",
            "/var/tmp/cydia.log",
            "/private/var/tmp/cydia.log"
        ]
        
        // Check both fileExists and isReadableFile
        for path in paths {
            if fileManager.fileExists(atPath: path) ||
               fileManager.isReadableFile(atPath: path) {
                return true
            }
        }
        
        return false
    }
    
    static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        // Make a mutable copy to pass to the closure
        var nameCopy = name
        let result = nameCopy.withUnsafeMutableBufferPointer {
            sysctl($0.baseAddress, u_int(name.count), &info, &size, nil, 0)
        }
        return result == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
    }
    
    static func skipDebugDevice() -> Bool {
        #if DEBUG
        return true
        #else
        return isDebuggerAttached()
        #endif
    }

    static func canWriteOutsideSandbox(fileManager: FileManager = .default) -> Bool {
        let testPath = "/private/jb_test_\(UUID().uuidString).txt"
        let testURL = URL(fileURLWithPath: testPath)
        let data = Data("test".utf8)
        
        do {
            try data.write(to: testURL, options: [.atomic])
            try fileManager.removeItem(at: testURL)
            return true  // Successfully wrote outside sandbox = jailbroken
        } catch {
            return false  // Failed to write = normal behavior
        }
    }
    
    static func hasInjectedDynamicLibraries() -> Bool {
        let suspiciousKeys = [
            "DYLD_INSERT_LIBRARIES",
            "DYLD_LIBRARY_PATH",
            "DYLD_FRAMEWORK_PATH",
            "_MSSafeMode"  // Mobile Substrate safe mode
        ]
        
        let environment = ProcessInfo.processInfo.environment
        
        for key in suspiciousKeys {
            if let value = environment[key], !value.isEmpty {
                return true
            }
        }
        
        return false
    }
    
    static func hasSuspiciousSymlinks(fileManager: FileManager = .default) -> Bool {
        let paths = [
            "/Applications",
            "/Library/Ringtones",
            "/Library/Wallpaper",
            "/usr/arm-apple-darwin9",
            "/usr/include",
            "/usr/libexec",
            "/usr/share"
        ]
        
        for path in paths {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: path)
                if let fileType = attributes[.type] as? FileAttributeType,
                   fileType == .typeSymbolicLink {
                    return true
                }
            } catch {
                continue
            }
        }
        
        return false
    }
    
    static func hasDyldInjection() -> Bool {
        let count = _dyld_image_count()

        for i in 0..<count {
            guard let cName = _dyld_get_image_name(i) else { continue }
            let name = String(cString: cName).lowercased()

            if name.contains("frida") ||
               name.contains("substrate") ||
               name.contains("libhooker") {
                return true
            }
        }
        return false
    }
    
    static func canOpenCydiaURL() -> Bool {
        // Check multiple jailbreak URL schemes
        let urlSchemes = [
            "cydia://package/com.example.package",
            "sileo://package/com.example.package",
            "zbra://package/com.example.package",
            "installer://install/com.example.package",
            "undecimus://"
        ]
        
        for scheme in urlSchemes {
            if let url = URL(string: scheme),
               UIApplication.shared.canOpenURL(url) {
                return true
            }
        }
        
        return false
    }
    
    // FIXED: Replace fork() with dyld check and stat syscall
    static func hasSuspiciousSystemCalls() -> Bool {
        // Check for loaded dynamic libraries
        let imageCount = _dyld_image_count()
        for i in 0..<imageCount {
            if let imageName = _dyld_get_image_name(i) {
                let name = String(cString: imageName).lowercased()
                
                // Check for suspicious library names
                let suspiciousLibs = [
                    "substrate",
                    "substitute",
                    "frida",
                    "cycript",
                    "cynject",
                    "libhooker"
                ]
                
                for suspiciousLib in suspiciousLibs {
                    if name.contains(suspiciousLib) {
                        return true
                    }
                }
            }
        }
        
        // Check if stat() can access restricted paths
        // On jailbroken devices, stat() may succeed for system paths
        return canStatRestrictedPaths()
    }
    
    static func canStatRestrictedPaths() -> Bool {
        let restrictedPaths = [
            "/bin/bash",
            "/usr/sbin/sshd",
            "/Applications/Cydia.app"
        ]
        
        for path in restrictedPaths {
            var statInfo = stat()
            if stat(path, &statInfo) == 0 {
                // stat succeeded - suspicious on non-jailbroken device
                return true
            }
        }
        
        return false
    }
}

// MARK: - Usage Example
extension JailbreakDetector {
    /// Perform jailbreak check with result handling
    static func performSecurityCheck(onJailbroken: () -> Void, onSecure: () -> Void) {
        if isJailbroken() {
            onJailbroken()
        } else {
            onSecure()
        }
    }
    
    /// Get detailed detection results for logging/debugging
    static func getDetectionDetails(fileManager: FileManager = .default) -> [String: Bool] {
        #if targetEnvironment(simulator)
        return ["simulator": true]
        #else
        return [
            "suspiciousFiles": hasSuspiciousFiles(fileManager: fileManager),
            "sandboxBypass": canWriteOutsideSandbox(fileManager: fileManager),
            "injectedLibs": hasInjectedDynamicLibraries(),
            "symlinks": hasSuspiciousSymlinks(fileManager: fileManager),
            "urlSchemes": canOpenCydiaURL(),
            "systemCalls": hasSuspiciousSystemCalls()
        ]
        #endif
    }
}

