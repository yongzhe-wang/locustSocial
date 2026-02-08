import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct RegisterView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var bio = ""
    @State private var errorMessage: String?
    @Binding var isLoggedIn: Bool

    private let db = Firestore.firestore()

    var body: some View {
        VStack(spacing: 24) {
            Text("Create Account")
                .font(.title).bold()

            VStack(spacing: 16) {
                TextField("Display Name", text: $displayName)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

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

                TextField("Bio (optional)", text: $bio)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Sign Up") {
                Task { await registerUser() }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .padding()
    }

    // MARK: - Register + Firestore setup
    private func registerUser() async {
        errorMessage = nil
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let user = result.user
            let handle = email.components(separatedBy: "@").first ?? "user"

            let userDoc: [String: Any] = [
                "id": user.uid,
                "displayName": displayName.isEmpty ? handle.capitalized : displayName,
                "handle": handle,
                "email": email,
                "bio": bio,
                "avatarURL": "",
                "createdAt": FieldValue.serverTimestamp()
            ]

            try await db.collection("users").document(user.uid).setData(userDoc)
            print("✅ Firestore user created for \(user.uid)")

            isLoggedIn = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
