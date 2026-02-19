import Foundation

enum Page: Hashable {
    case home
    case history
    case options
    case about
    case info
}

@Observable @MainActor
final class NavigationManager {
    private(set) var currentPage: Page = .home
    private(set) var isTransitioning = false
    var pageStack: [Page] = []

    func navigate(to page: Page, using controller: GridController, renderer: PageRenderer) {
        guard !isTransitioning, page != currentPage else { return }
        isTransitioning = true

        let previousPage = currentPage
        pageStack.append(previousPage)

        performWipeTransition(using: controller, renderer: renderer) { [weak self] in
            self?.currentPage = page
        }
    }

    func goBack(using controller: GridController, renderer: PageRenderer, onComplete: (() -> Void)? = nil) {
        guard !isTransitioning, let previousPage = pageStack.popLast() else { return }
        isTransitioning = true

        performWipeTransition(using: controller, renderer: renderer, onComplete: onComplete) { [weak self] in
            self?.currentPage = previousPage
        }
    }

    /// Reset to home without animation (e.g. before entering capture from a non-home page).
    func resetToHome() {
        pageStack.removeAll()
        currentPage = .home
    }

    /// Navigate to home with a wipe transition, clearing the page stack.
    func navigateToHome(using controller: GridController, renderer: PageRenderer, onComplete: (() -> Void)? = nil) {
        guard !isTransitioning, currentPage != .home else { return }
        isTransitioning = true
        pageStack.removeAll()

        performWipeTransition(using: controller, renderer: renderer, onComplete: onComplete) { [weak self] in
            self?.currentPage = .home
        }
    }

    // MARK: - Wipe Transition

    /// Standard page transition: wipe out cell-by-cell, swap content while covered, wipe in to reveal.
    private func performWipeTransition(
        using controller: GridController,
        renderer: PageRenderer,
        onComplete: (() -> Void)? = nil,
        pageUpdate: @escaping () -> Void
    ) {
        guard let grid = controller.grid else {
            isTransitioning = false
            return
        }

        controller.wipe.wipeOut(on: grid) { [weak self] in
            guard let self, let grid = controller.grid else { return }

            pageUpdate()

            grid.clearLayer(.content)
            grid.clearLayer(.structure)
            renderer.renderStructure(into: grid)
            renderer.renderContent(into: grid)
            grid.render()

            controller.wipe.wipeIn(on: grid) { [weak self] in
                self?.isTransitioning = false
                onComplete?()
            }
        }
    }
}
