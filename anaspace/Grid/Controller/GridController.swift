import Foundation

@Observable @MainActor
final class GridController {
    var grid: CharacterGrid?
    var isObserving = false
    let cascade = CascadeAnimation()
    let observe = ObserveAnimation()

    func triggerCascade() {
        guard let grid else { return }
        cascade.run(on: grid) {}
    }

    func triggerObserve(restore: @escaping (CharacterGrid) -> Void) {
        guard let grid, !isObserving else { return }
        isObserving = true
        observe.run(on: grid) { [weak self, weak grid] in
            self?.isObserving = false
            guard let grid else { return }
            restore(grid)
        }
    }
}
