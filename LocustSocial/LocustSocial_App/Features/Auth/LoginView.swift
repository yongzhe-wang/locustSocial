// Features/Auth/LoginView.swift
import SwiftUI
import FirebaseAuth

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    @Binding var isLoggedIn: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                // App logo or title
                Image(systemName: "leaf.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.green)
                Text("LocustSocial")
                    .font(.largeTitle).bold()
                
                // Input fields
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    
                    SecureField("Password", text: $password)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                }
                
                // Error message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Login button
                Button {
                    Task { await login() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    } else {
                        Text("Log In")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
                
                // Register link
                NavigationLink("Don’t have an account? Sign Up", destination: RegisterView(isLoggedIn: $isLoggedIn))
                    .font(.footnote)
                    .padding(.top, 8)
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func login() async {
        isLoading = true
        errorMessage = nil
        print("🟢 login() called with email:", email)

        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
            print("✅ Auth sign-in success for:", Auth.auth().currentUser?.email ?? "nil")

            await MainActor.run {
                isLoggedIn = true
                print("🟣 isLoggedIn flipped to true")
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                print("❌ login() failed:", error.localizedDescription)
            }
        }

        isLoading = false
        print("🟠 login() finished. isLoggedIn:", isLoggedIn)
    }


}
