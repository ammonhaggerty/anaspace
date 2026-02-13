import SwiftUI

@Observable
final class GridController {
    var grid: CharacterGrid?
    let cascade = CascadeAnimation()

    func triggerCascade() {
        guard let grid else { return }
        cascade.run(on: grid)
    }
}

struct CharacterGridView: UIViewRepresentable {
    let controller: GridController
    let onReady: (CharacterGrid) -> Void

    func makeUIView(context: Context) -> CharacterGrid {
        let grid = CharacterGrid()
        controller.grid = grid

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        grid.addGestureRecognizer(tap)

        return grid
    }

    func updateUIView(_ uiView: CharacterGrid, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    final class Coordinator: NSObject {
        let controller: GridController

        init(controller: GridController) {
            self.controller = controller
        }

        @objc func handleTap() {
            controller.triggerCascade()
        }
    }

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
