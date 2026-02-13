import Foundation

@MainActor
protocol PageRenderer {
    var page: Page { get }
    func renderStructure(into grid: CharacterGrid)
    func renderContent(into grid: CharacterGrid)
}
