struct LoginView: View {
    @StateObject private var viewModel = TestLoginViewModel()
    
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
