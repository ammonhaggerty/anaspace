import SwiftUI

// MARK: - Bottom Nav Bar

struct BottomNavBar: View {
    var isObserving: Bool = false
    var onObserveTap: () -> Void = {}
    var onHistoryTap: () -> Void = {}
    var onOptionsTap: () -> Void = {}
    var onHoldStart: () -> Void = {}
    var onHoldEnd: () -> Void = {}

    private let navDark = GridColor.bold.uiColor.swiftUI
    private let bg = GridColor.background.uiColor.swiftUI
    private let tint = GridColor.tint.uiColor.swiftUI
    private let red = GridColor.focus.uiColor.swiftUI

    var body: some View {
        HStack {
            if !isObserving {
                NavButton(iconName: "icon-history", fg: tint, bg: navDark, onTap: onHistoryTap)
            }

            Spacer()

            ObserveButton(
                isObserving: isObserving,
                navDark: navDark,
                idle: tint,
                red: red,
                onTap: onObserveTap,
                onHoldStart: onHoldStart,
                onHoldEnd: onHoldEnd
            )

            Spacer()

            if !isObserving {
                NavButton(iconName: "icon-options", fg: tint, bg: navDark, onTap: onOptionsTap)
            }
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 16)
    }
}

// MARK: - Nav Button with Hit State

struct NavButton: View {
    let iconName: String
    let fg: Color
    let bg: Color
    var onTap: () -> Void = {}

    @State private var isPressed = false

    var body: some View {
        Circle()
            .fill(bg)
            .frame(width: 44, height: 44)
            .overlay(
                Image(iconName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(fg)
            )
            .scaleEffect(isPressed ? 0.88 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in
                        isPressed = false
                        onTap()
                    }
            )
    }
}

// MARK: - Nav Text Button

struct NavTextButton: View {
    let label: String
    let fg: Color
    let bg: Color
    var onTap: () -> Void = {}

    @State private var isPressed = false

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(fg)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Capsule().fill(bg))
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in
                        isPressed = false
                        onTap()
                    }
            )
    }
}

// MARK: - Observe Button with Pulse

struct ObserveButton: View {
    let isObserving: Bool
    let navDark: Color
    let idle: Color
    let red: Color
    let onTap: () -> Void
    var onHoldStart: () -> Void = {}
    var onHoldEnd: () -> Void = {}

    @State private var isPressed = false
    @State private var isPulsing = false
    @State private var holdTimer: Timer?
    @State private var isHolding = false

    var body: some View {
        Circle()
            .fill(navDark)
            .frame(width: 62, height: 62)
            .overlay(
                Circle()
                    .fill(isObserving ? red : idle)
                    .frame(width: 26, height: 26)
                    .scaleEffect(isPulsing ? 1.1 : 1.0)
                    .animation(
                        isPulsing
                            ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                            : .easeInOut(duration: 0.15),
                        value: isPulsing
                    )
            )
            .scaleEffect(isPressed ? 0.88 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isPressed)
            .onChange(of: isObserving) { _, active in
                isPulsing = active
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            onTap()  // Fires immediately — starts capture
                            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                                Task { @MainActor in
                                    isHolding = true
                                    onHoldStart()  // Upgrade to hold
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        holdTimer?.invalidate()
                        holdTimer = nil
                        if isHolding {
                            isHolding = false
                            onHoldEnd()  // End capture
                        }
                        // Tap mode: no action on release (continues on its own)
                    }
            )
    }
}

// MARK: - Color Bridge

extension UIColor {
    var swiftUI: Color { Color(uiColor: self) }
}
