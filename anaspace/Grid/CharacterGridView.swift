import SwiftUI

struct CharacterGridView: UIViewRepresentable {
    let controller: GridController
    let onReady: (CharacterGrid) -> Void

    func makeUIView(context: Context) -> CharacterGrid {
        let grid = CharacterGrid()
        controller.grid = grid
        return grid
    }

    func updateUIView(_ uiView: CharacterGrid, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CharacterGrid, context: Context) -> CGSize? {
        // After first layout, notify the app so it can populate layers
        DispatchQueue.main.async {
            if uiView.rowCount > 0 {
                onReady(uiView)
            }
        }
        return nil // fill available space
    }
}
