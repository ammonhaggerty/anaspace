import Foundation

@MainActor
protocol GridAnimation: AnyObject {
    var isRunning: Bool { get }
    func run(on grid: CharacterGrid, completion: @escaping () -> Void)
    func cancel()
}
