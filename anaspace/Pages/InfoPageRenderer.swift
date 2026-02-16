import Foundation

@MainActor
final class InfoPageRenderer: PageRenderer {
    let page: Page = .info
    let hiddenStructureRows: Set<Int> = []

    enum Mode {
        case subject
        case entity
    }

    var mode: Mode = .subject

    // Subject mode
    var subjectName: String = ""
    var birthInfo: String = ""
    var bio: String = ""

    // Entity mode
    var entityName: String = ""
    var entityType: EntityType = .peer
    var relationship: String = ""
    var entityDescription: String = ""

    private let layout = FormalContentLayout()

    func renderStructure(into grid: CharacterGrid) {
        let cols = GridMetrics.columns
        for row in 0..<grid.rowCount {
            for col in 0..<cols {
                grid.setCell(
                    layer: .structure, row: row, col: col,
                    state: CellState(character: "\u{2591}", color: .tint, bold: false)
                )
            }
        }
    }

    func renderContent(into grid: CharacterGrid) {
        switch mode {
        case .subject:
            renderSubject(into: grid)
        case .entity:
            renderEntity(into: grid)
        }
    }

    private func renderSubject(into grid: CharacterGrid) {
        let sections: [ContentSection] = [
            .spacer,
            .header(subjectName),
            .spacer,
            .paragraph(birthInfo),
            .spacer,
            .paragraph(bio),
        ]
        layout.render(sections: sections, into: grid, startRow: 0)
    }

    private func renderEntity(into grid: CharacterGrid) {
        let titleWithGlyph = "\(entityType.glyph) \(entityName)"
        let sections: [ContentSection] = [
            .spacer,
            .header(titleWithGlyph),
            .spacer,
            .paragraph(relationship),
            .spacer,
            .paragraph(entityDescription),
        ]
        layout.render(sections: sections, into: grid, startRow: 0)
    }

    func configureForEntity(_ connection: CultureConnection) {
        mode = .entity
        entityName = connection.name
        entityType = connection.entityType
        relationship = connection.relationship
        entityDescription = connection.description
    }

    func configureForSubject(name: String, birthInfo: String, bio: String) {
        mode = .subject
        subjectName = name
        self.birthInfo = birthInfo
        self.bio = bio
    }
}
