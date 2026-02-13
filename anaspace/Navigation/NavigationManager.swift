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

        // Run cascade transition on transition layer
        controller.cascade.run(on: controller.grid!) { [weak self] in
            guard let self else { return }
            // While covered by transition: swap content
            self.currentPage = page
            if let grid = controller.grid {
                grid.clearLayer(.content)
                renderer.renderContent(into: grid)
                grid.render()
            }
            self.isTransitioning = false
        }
    }

    func goBack(using controller: GridController, renderer: PageRenderer) {
        guard !isTransitioning, let previousPage = pageStack.popLast() else { return }
        isTransitioning = true

        controller.cascade.run(on: controller.grid!) { [weak self] in
            guard let self else { return }
            self.currentPage = previousPage
            if let grid = controller.grid {
                grid.clearLayer(.content)
                renderer.renderContent(into: grid)
                grid.render()
            }
            self.isTransitioning = false
        }
    }
}
