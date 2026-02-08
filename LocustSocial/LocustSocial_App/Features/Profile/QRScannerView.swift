import SwiftUI
import AVFoundation

struct QRScannerView: View {
    @State private var scannedCode: String = "No code yet"

    var body: some View {
        VStack(spacing: 20) {
            Text("QR Scanner")
                .font(.title).bold()

            Text(scannedCode)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)

            Spacer()
        }
        .padding()
        .navigationTitle("Scan QR")
        .navigationBarTitleDisplayMode(.inline)
    }
}
