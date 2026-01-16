import PhotosUI
import SwiftUI

struct PhotoPicker: View {
    var image: Binding<UIImage?>?
    var images: Binding<[UIImage]>?
    
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(
            "Select Photo(s)",
            selection: $selectedItems,
            maxSelectionCount: images != nil ? 10 : 1,
            matching: .images
        )
        .onChange(of: selectedItems) { oldValue, newItems in
            Task {
                var loadedImages: [UIImage] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        loadedImages.append(uiImage)
                    }
                }
                
                await MainActor.run {
                    if let imageBinding = image, let first = loadedImages.first {
                        imageBinding.wrappedValue = first
                    } else if let imagesBinding = images {
                        imagesBinding.wrappedValue.append(contentsOf: loadedImages)
                    }
                    // Optional: Clear selection to allow re-picking same photos if needed
                    // selectedItems = [] 
                }
            }
        }
    }
}
