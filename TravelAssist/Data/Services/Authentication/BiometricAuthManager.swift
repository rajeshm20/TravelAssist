//import SwiftUI
//import LocalAuthentication
//import Combine
//
//// MARK: - Biometric Authentication Manager
//final class BiometricAuthManager: ObservableObject {
//    @Published var authState: AuthState = .notAuthenticated
//    @Published var showError: Bool = false
//    @Published var errorMessage: String = ""
//    
//    private let context = LAContext()
//    private let secureStorage: SecureStorageProtocol
//    private let sessionManager: SessionManager
//    
//    enum AuthState {
//        case notAuthenticated
//        case authenticating
//        case authenticated
//        case failed(BiometricError)
//    }
//    
//    enum BiometricError: LocalizedError {
//        case notAvailable
//        case notEnrolled
//        case authenticationFailed
//        case tooManyAttempts
//        case userCancel
//        
//        var errorDescription: String? {
//            switch self {
//            case .notAvailable: return "Biometric authentication not available on this device"
//            case .notEnrolled: return "Please enable Face ID/Touch ID in Settings"
//            case .authenticationFailed: return "Authentication failed. Please try again."
//            case .tooManyAttempts: return "Too many attempts. Please use passcode."
//            case .userCancel: return "Authentication cancelled"
//            }
//        }
//    }
//    
//    init(secureStorage: SecureStorageProtocol, sessionManager: SessionManager) {
//        self.secureStorage = secureStorage
//        self.sessionManager = sessionManager
//    }
//    
//    // MARK: Check Biometric Availability
//    func checkBiometricAvailability() -> Bool {
//        var error: NSError?
//        let canEvaluate = context.canEvaluatePolicy(
//            .deviceOwnerAuthenticationWithBiometrics,
//            error: &error
//        )
//        
//        if let error = error {
//            handleLAError(error)
//            return false
//        }
//        
//        return canEvaluate
//    }
//    
//    // MARK: Authenticate
//    func authenticate() {
//        guard checkBiometricAvailability() else {
//            authState = .failed(.notAvailable)
//            return
//        }
//        
//        authState = .authenticating
//        
//        // Banking requirement: Invalidate after 30 seconds inactivity
//        context.touchIDAuthenticationAllowableReuseDuration = 0
//        
//        let reason = "Authenticate to access your BNP Paribas account"
//        
//        context.evaluatePolicy(
//            .deviceOwnerAuthenticationWithBiometrics,
//            localizedReason: reason
//        ) { [weak self] success, error in
//            DispatchQueue.main.async {
//                if success {
//                    self?.handleSuccessfulAuth()
//                } else if let error = error {
//                    self?.handleLAError(error as NSError)
//                }
//            }
//        }
//    }
//    
//    // MARK: Success Handler
//    private func handleSuccessfulAuth() {
//        // 1. Retrieve encrypted session token
//        guard let encryptedToken = try? secureStorage.retrieve(key: "session_token") else {
//            authState = .failed(.authenticationFailed)
//            return
//        }
//        
//        // 2. Decrypt and validate session
//        do {
//            let sessionToken = try decrypt(encryptedToken)
//            try sessionManager.restoreSession(token: sessionToken)
//            
//            // 3. Log security event (banking compliance)
//            logAuthenticationEvent(success: true)
//            
//            authState = .authenticated
//        } catch {
//            authState = .failed(.authenticationFailed)
//            logAuthenticationEvent(success: false, error: error)
//        }
//    }
//    
//    // MARK: Error Handler
//    private func handleLAError(_ error: NSError) {
//        let biometricError: BiometricError
//        
//        switch error.code {
//        case LAError.biometryNotAvailable.rawValue:
//            biometricError = .notAvailable
//        case LAError.biometryNotEnrolled.rawValue:
//            biometricError = .notEnrolled
//        case LAError.authenticationFailed.rawValue:
//            biometricError = .authenticationFailed
//        case LAError.userCancel.rawValue, LAError.appCancel.rawValue:
//            biometricError = .userCancel
//        case LAError.biometryLockout.rawValue:
//            biometricError = .tooManyAttempts
//        default:
//            biometricError = .authenticationFailed
//        }
//        
//        authState = .failed(biometricError)
//        errorMessage = biometricError.localizedDescription
//        showError = true
//        
//        logAuthenticationEvent(success: false, error: error)
//    }
//    
//    // MARK: Security Logging
//    private func logAuthenticationEvent(success: Bool, error: Error? = nil) {
//        let event = SecurityEvent(
//            type: .biometricAuth,
//            success: success,
//            timestamp: Date(),
//            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown",
//            error: error?.localizedDescription
//        )
//        
//        // Send to banking security monitoring system
//        SecurityLogger.shared.log(event)
//    }
//    
//    private func decrypt(_ data: Data) throws -> String {
//        // Implementation using CryptoKit
//        return ""
//    }
//}
//
//// MARK: - SwiftUI Login View
//struct BiometricLoginView: View {
//    @StateObject private var authManager: BiometricAuthManager
//    @State private var showPasscodeLogin = false
//    
//    init(authManager: BiometricAuthManager) {
//        _authManager = StateObject(wrappedValue: authManager)
//    }
//    
//    var body: some View {
//        ZStack {
//            // BNP Paribas brand background
//            LinearGradient(
//                colors: [Color.bnpGreen, Color.bnpDarkGreen],
//                startPoint: .topLeading,
//                endPoint: .bottomTrailing
//            )
//            .ignoresSafeArea()
//            
//            VStack(spacing: 30) {
//                // Logo
//                Image("bnp_logo")
//                    .resizable()
//                    .scaledToFit()
//                    .frame(width: 200, height: 100)
//                    .accessibilityLabel("BNP Paribas Logo")
//                
//                // Authentication State UI
//                authenticationContent
//                
//                // Alternative Login
//                Button("Use Passcode Instead") {
//                    showPasscodeLogin = true
//                }
//                .foregroundColor(.white)
//                .font(.subheadline)
//            }
//            .padding()
//        }
//        .alert("Authentication Error", isPresented: $authManager.showError) {
//            Button("OK", role: .cancel) { }
//            if case .failed(.notEnrolled) = authManager.authState {
//                Button("Open Settings") {
//                    openSettings()
//                }
//            }
//        } message: {
//            Text(authManager.errorMessage)
//        }
//        .sheet(isPresented: $showPasscodeLogin) {
//            PasscodeLoginView()
//        }
//        .onAppear {
//            // Auto-trigger biometric on appear (banking UX pattern)
//            if authManager.checkBiometricAvailability() {
//                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
//                    authManager.authenticate()
//                }
//            }
//        }
//    }
//    
//    @ViewBuilder
//    private var authenticationContent: some View {
//        switch authManager.authState {
//        case .notAuthenticated:
//            VStack(spacing: 20) {
//                biometricIcon
//                
//                Text("Secure Login")
//                    .font(.title2)
//                    .foregroundColor(.white)
//                
//                Button(action: { authManager.authenticate() }) {
//                    HStack {
//                        Image(systemName: "faceid")
//                        Text("Authenticate with Face ID")
//                    }
//                    .padding()
//                    .frame(maxWidth: .infinity)
//                    .background(Color.white)
//                    .foregroundColor(.bnpGreen)
//                    .cornerRadius(12)
//                }
//                .accessibilityLabel("Authenticate with biometrics")
//            }
//            
//        case .authenticating:
//            VStack(spacing: 20) {
//                ProgressView()
//                    .scaleEffect(1.5)
//                    .tint(.white)
//                
//                Text("Authenticating...")
//                    .foregroundColor(.white)
//            }
//            
//        case .authenticated:
//            VStack(spacing: 20) {
//                Image(systemName: "checkmark.circle.fill")
//                    .font(.system(size: 60))
//                    .foregroundColor(.white)
//                
//                Text("Authentication Successful")
//                    .foregroundColor(.white)
//                    .font(.title3)
//            }
//            
//        case .failed(let error):
//            VStack(spacing: 20) {
//                Image(systemName: "xmark.circle.fill")
//                    .font(.system(size: 60))
//                    .foregroundColor(.red)
//                
//                Text(error.localizedDescription)
//                    .foregroundColor(.white)
//                    .multilineTextAlignment(.center)
//                    .padding()
//                
//                Button("Try Again") {
//                    authManager.authenticate()
//                }
//                .padding()
//                .background(Color.white)
//                .foregroundColor(.bnpGreen)
//                .cornerRadius(12)
//            }
//        }
//    }
//    
//    private var biometricIcon: some View {
//        let biometryType = LAContext().biometryType
//        let iconName = biometryType == .faceID ? "faceid" : "touchid"
//        
//        return Image(systemName: iconName)
//            .font(.system(size: 60))
//            .foregroundColor(.white)
//    }
//    
//    private func openSettings() {
//        if let url = URL(string: UIApplication.openSettingsURLString) {
//            UIApplication.shared.open(url)
//        }
//    }
//}
//
//// MARK: - Secure Storage Implementation
//protocol SecureStorageProtocol {
//    func store(key: String, value: Data) throws
//    func retrieve(key: String) throws -> Data
//    func delete(key: String) throws
//}
//
//final class KeychainStorage: SecureStorageProtocol {
//    func store(key: String, value: Data) throws {
//        let query: [String: Any] = [
//            kSecClass as String: kSecClassGenericPassword,
//            kSecAttrAccount as String: key,
//            kSecValueData as String: value,
//            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
//            // Banking security: Require biometric for access
//            kSecAttrAccessControl as String: try createAccessControl()
//        ]
//        
//        SecItemDelete(query as CFDictionary)
//        let status = SecItemAdd(query as CFDictionary, nil)
//        
//        guard status == errSecSuccess else {
//            throw KeychainError.unhandledError(status: status)
//        }
//    }
//    
//    func retrieve(key: String) throws -> Data {
//        let query: [String: Any] = [
//            kSecClass as String: kSecClassGenericPassword,
//            kSecAttrAccount as String: key,
//            kSecReturnData as String: true,
//            kSecMatchLimit as String: kSecMatchLimitOne
//        ]
//        
//        var result: AnyObject?
//        let status = SecItemCopyMatching(query as CFDictionary, &result)
//        
//        guard status == errSecSuccess,
//              let data = result as? Data else {
//            throw KeychainError.itemNotFound
//        }
//        
//        return data
//    }
//    
//    func delete(key: String) throws {
//        let query: [String: Any] = [
//            kSecClass as String: kSecClassGenericPassword,
//            kSecAttrAccount as String: key
//        ]
//        
//        let status = SecItemDelete(query as CFDictionary)
//        guard status == errSecSuccess || status == errSecItemNotFound else {
//            throw KeychainError.unhandledError(status: status)
//        }
//    }
//    
//    private func createAccessControl() throws -> SecAccessControl {
//        var error: Unmanaged<CFError>?
//        
//        guard let access = SecAccessControlCreateWithFlags(
//            nil,
//            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
//            .biometryCurrentSet, // Invalidates if biometry changes
//            &error
//        ) else {
//            throw error!.takeRetainedValue() as Error
//        }
//        
//        return access
//    }
//}
//
//enum KeychainError: Error {
//    case itemNotFound
//    case unhandledError(status: OSStatus)
//}
