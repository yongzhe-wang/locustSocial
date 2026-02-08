import PhotosUI
import SwiftUI



struct PhotoPicker: View {
    @Binding var image: UIImage?
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker("Select Photo", selection: $selectedItem, matching: .images)
            .onChange(of: selectedItem) { oldValue, newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        image = uiImage
                    }
                }
            }
    }
}
