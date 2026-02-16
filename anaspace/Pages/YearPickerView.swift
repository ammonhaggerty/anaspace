import SwiftUI

struct YearPickerView: View {
    let initialYear: Int
    let onYearSelected: (Int) -> Void
    let onDismiss: () -> Void

    @State private var scrollPosition: Double
    @State private var dragStartPosition: Double?

    private static let minYear = 1900
    private static let maxYear = Calendar.current.component(.year, from: Date())

    // Layout
    private let baseDigitHeight: CGFloat = 90
    private let minScale: CGFloat = 0.22
    private let scaleDecayRate: Double = 0.55
    private let gap: CGFloat = 6
    private let digitAspect: CGFloat = 2.0 / 3.0

    // Drag
    private let pixelsPerYear: CGFloat = 60
    private let velocityMultiplier: Double = 4.0

    // Colors
    private let navDark = GridColor.bold.uiColor.swiftUI
    private let navFg = GridColor.background.uiColor.swiftUI

    // Pre-loaded digit images (dark and white-tinted for selection)
    private let digitImages: [UIImage]
    private let selectedDigitImages: [UIImage]

    init(initialYear: Int, onYearSelected: @escaping (Int) -> Void, onDismiss: @escaping () -> Void) {
        self.initialYear = initialYear
        self.onYearSelected = onYearSelected
        self.onDismiss = onDismiss
        self._scrollPosition = State(initialValue: Double(initialYear))

        var images: [UIImage] = []
        var selImages: [UIImage] = []
        let white = GridColor.highlight.uiColor
        for i in 0...9 {
            let img = UIImage(named: "year\(i)") ?? UIImage()
            images.append(img)
            selImages.append(Self.tintImage(img, with: white))
        }
        self.digitImages = images
        self.selectedDigitImages = selImages
    }

    private var selectedYear: Int {
        Int(min(Double(Self.maxYear), max(Double(Self.minYear), scrollPosition)).rounded())
    }

    private func scale(forYearDistance d: Double) -> CGFloat {
        minScale + (1.0 - minScale) * CGFloat(exp(-abs(d) * scaleDecayRate))
    }

    private static func tintImage(_ image: UIImage, with color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size))
            image.draw(in: CGRect(origin: .zero, size: image.size), blendMode: .destinationIn, alpha: 1)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let selectionY = geo.size.height / 3
            let rightEdge = geo.size.width - GridMetrics.sideMargin

            ZStack {
                GridColor.background.uiColor.swiftUI
                    .ignoresSafeArea()

                Canvas { context, size in
                    drawYears(
                        context: &context,
                        selectionY: selectionY,
                        rightEdge: rightEdge,
                        screenHeight: size.height
                    )
                }

                // Tap on selected year to confirm
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 200, height: 80)
                    .position(x: geo.size.width - GridMetrics.sideMargin - 100, y: selectionY)
                    .onTapGesture {
                        onYearSelected(selectedYear)
                        onDismiss()
                    }

                // Bottom nav
                HStack {
                    NavButton(iconName: "arrow-back", fg: navFg, bg: navDark) {
                        onYearSelected(selectedYear)
                        onDismiss()
                    }
                    Spacer()
                }
                .padding(.horizontal, 40)
                .frame(width: geo.size.width, height: GridMetrics.bottomFooter)
                .position(
                    x: geo.size.width / 2,
                    y: geo.size.height - GridMetrics.bottomFooter / 2
                )
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartPosition == nil {
                            dragStartPosition = scrollPosition
                        }
                        let yearDelta = Double(value.translation.height) / Double(pixelsPerYear)
                        // Drag up (negative translation) → decrease scrollPosition → older years
                        // New at top, old at bottom: drag up reveals older years below
                        let newPos = (dragStartPosition ?? scrollPosition) + yearDelta
                        scrollPosition = min(Double(Self.maxYear), max(Double(Self.minYear), newPos))
                    }
                    .onEnded { value in
                        dragStartPosition = nil

                        // Momentum: amplify the predicted remaining motion
                        let remainingPts = Double(value.predictedEndTranslation.height - value.translation.height)
                        let remainingYears = remainingPts / Double(pixelsPerYear)
                        let momentum = remainingYears * velocityMultiplier

                        let target = scrollPosition + momentum
                        let clamped = min(Double(Self.maxYear), max(Double(Self.minYear), target))
                        let snapped = clamped.rounded()

                        // Longer animation for bigger throws → deceleration feel
                        let distance = abs(snapped - scrollPosition)
                        let response = min(2.5, 0.3 + distance * 0.015)
                        withAnimation(.spring(response: response, dampingFraction: 0.92)) {
                            scrollPosition = snapped
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .statusBarHidden()
    }

    // MARK: - Year Rendering

    private func drawYears(
        context: inout GraphicsContext,
        selectionY: CGFloat,
        rightEdge: CGFloat,
        screenHeight: CGFloat
    ) {
        let selected = selectedYear
        let floorYear = Int(floor(scrollPosition))
        let frac = CGFloat(scrollPosition - Double(floorYear))

        // Heights of the two years straddling the selection point
        let floorH = baseDigitHeight * scale(forYearDistance: Double(frac))
        let ceilH = baseDigitHeight * scale(forYearDistance: Double(1 - frac))
        let totalSpace = floorH / 2 + gap + ceilH / 2

        // New at top: ceilYear (newer, floorYear+1) is ABOVE, floorYear (older) is BELOW
        let floorCenterY = selectionY + frac * totalSpace
        let ceilCenterY = selectionY - (1 - frac) * totalSpace

        // Draw floor year
        if floorYear >= Self.minYear {
            drawDigits(year: floorYear, centerY: floorCenterY, height: floorH,
                       isSelected: floorYear == selected, rightEdge: rightEdge, context: &context)
        }

        // Draw ceil year
        let ceilYear = floorYear + 1
        if ceilYear <= Self.maxYear {
            drawDigits(year: ceilYear, centerY: ceilCenterY, height: ceilH,
                       isSelected: ceilYear == selected, rightEdge: rightEdge, context: &context)
        }

        // Stack ABOVE ceilYear (newer years, going upward)
        var aboveEdge = ceilCenterY - ceilH / 2
        for year in stride(from: floorYear + 2, through: Self.maxYear, by: 1) {
            let dist = abs(Double(year) - scrollPosition)
            let s = scale(forYearDistance: dist)
            let h = baseDigitHeight * s
            let centerY = aboveEdge - gap - h / 2
            if centerY + h / 2 < -50 { break }
            drawDigits(year: year, centerY: centerY, height: h,
                       isSelected: year == selected, rightEdge: rightEdge, context: &context)
            aboveEdge = centerY - h / 2
        }

        // Stack BELOW floorYear (older years, going downward)
        var belowEdge = floorCenterY + floorH / 2
        for year in stride(from: floorYear - 1, through: Self.minYear, by: -1) {
            let dist = abs(Double(year) - scrollPosition)
            let s = scale(forYearDistance: dist)
            let h = baseDigitHeight * s
            let centerY = belowEdge + gap + h / 2
            if centerY - h / 2 > screenHeight + 50 { break }
            drawDigits(year: year, centerY: centerY, height: h,
                       isSelected: year == selected, rightEdge: rightEdge, context: &context)
            belowEdge = centerY + h / 2
        }
    }

    private func drawDigits(
        year: Int,
        centerY: CGFloat,
        height: CGFloat,
        isSelected: Bool,
        rightEdge: CGFloat,
        context: inout GraphicsContext
    ) {
        let digits: [Int]
        if isSelected {
            digits = [year / 1000, (year / 100) % 10, (year / 10) % 10, year % 10]
        } else {
            digits = [(year / 10) % 10, year % 10]
        }

        let digitW = height * digitAspect
        let totalWidth = CGFloat(digits.count) * digitW
        let startX = rightEdge - totalWidth
        let top = centerY - height / 2
        let imgs = isSelected ? selectedDigitImages : digitImages

        for (i, digit) in digits.enumerated() {
            let rect = CGRect(
                x: startX + CGFloat(i) * digitW,
                y: top,
                width: digitW,
                height: height
            )
            context.draw(Image(uiImage: imgs[digit]), in: rect)
        }
    }
}
