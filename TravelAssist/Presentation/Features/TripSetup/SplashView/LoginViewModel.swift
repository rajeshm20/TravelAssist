import SwiftUI
import Combine

class LoginViewModel: ObservableObject {
    // Input fields
    @Published var email: String = ""
    @Published var password: String = ""
    
    // Validation states
    @Published var emailError: String?
    @Published var passwordError: String?
    @Published var isFormValid: Bool = false
    
    // UI states
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isLoggedIn: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupValidation()
    }
    
    private func setupValidation() {
        // Email validation pipeline
        $email
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .map { [weak self] email -> String? in
                guard !email.isEmpty else { return nil }
                guard self?.isValidEmail(email) == true else {
                    return "Please enter a valid email address"
                }
                return nil
            }
            .assign(to: &$emailError)
        
        // Password validation pipeline
        $password
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .map { password -> String? in
                guard !password.isEmpty else { return nil }
                if password.count < 8 {
                    return "Password must be at least 8 characters"
                }
                if !password.contains(where: { $0.isUppercase }) {
                    return "Must contain at least one uppercase letter"
                }
                if !password.contains(where: { $0.isNumber }) {
                    return "Must contain at least one number"
                }
                return nil
            }
            .assign(to: &$passwordError)
        
        // Form validity pipeline
        Publishers.CombineLatest($email, $password)
            .map { [weak self] email, password in
                guard let self = self else { return false }
                return !email.isEmpty && 
                       !password.isEmpty &&
                       self.isValidEmail(email) &&
                       password.count >= 8 &&
                       password.contains(where: { $0.isUppercase }) &&
                       password.contains(where: { $0.isNumber })
            }
            .assign(to: &$isFormValid)
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let regex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", regex).evaluate(with: email)
    }
    
    func login() {
        guard isFormValid else { return }
        
        isLoading = true
        errorMessage = nil
        
        // Simulate network request with Combine
        Future<Bool, Error> { promise in
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                // Simulate 90% success rate
                Bool.random() ? promise(.success(true)) : 
                promise(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid credentials"])))
            }
        }
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            },
            receiveValue: { [weak self] success in
                withAnimation { self?.isLoggedIn = success }
            }
        )
        .store(in: &cancellables)
    }
}

struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue.gradient)
                        
                        Text("Welcome Back")
                            .font(.largeTitle.bold())
                        
                        Text("Sign in to your account")
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                    
                    // Form
                    VStack(spacing: 16) {
                        // Email Field
                        ValidationTextField(
                            title: "Email",
                            text: $viewModel.email,
                            error: viewModel.emailError,
                            keyboardType: .emailAddress,
                            autocapitalization: .none
                        )
                        
                        // Password Field
                        ValidationSecureField(
                            title: "Password",
                            text: $viewModel.password,
                            error: viewModel.passwordError
                        )
                    }
                    .padding(.horizontal)
                    
                    // Server Error
                    if let error = viewModel.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                            Text(error)
                        }
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .padding(.horizontal)
                    }
                    
                    // Login Button
                    Button(action: viewModel.login) {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.isFormValid ? Color.blue : Color.gray.opacity(0.5))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!viewModel.isFormValid || viewModel.isLoading)
                    .padding(.horizontal)
                    
                    // Forgot Password
                    Button("Forgot Password?") {}
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    // Sign Up
                    HStack {
                        Text("Don't have an account?")
                            .foregroundColor(.secondary)
                        Button("Sign Up") {}
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                }
                
                // Success Overlay
                if viewModel.isLoggedIn {
                    SuccessOverlay()
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Reusable Components

struct ValidationTextField: View {
    let title: String
    @Binding var text: String
    let error: String?
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: UITextAutocapitalizationType = .sentences
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(title, text: $text)
                .keyboardType(keyboardType)
                .autocapitalization(autocapitalization)
                .disableAutocorrection(true)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(error != nil ? Color.red : Color.clear, lineWidth: 1)
                )
            
            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
        }
    }
}

struct ValidationSecureField: View {
    let title: String
    @Binding var text: String
    let error: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SecureField(title, text: $text)
                .textContentType(.password)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(error != nil ? Color.red : Color.clear, lineWidth: 1)
                )
            
            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
        }
    }
}

struct SuccessOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                
                Text("Login Successful!")
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
    }
}

// Preview
struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
    }
}
