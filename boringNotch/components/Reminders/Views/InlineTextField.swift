//
//  InlineTextField.swift
//  boringNotch
//
//  A text field that looks inline in the notch's SwiftUI content but is actually backed
//  by a separate, ordinary key-able NSPanel positioned exactly on top of it.
//
//  The notch's own window (BoringNotchSkyLightWindow) is deliberately never key -- it also
//  does private SkyLight space delegation, and making IT key directly (an earlier attempt)
//  broke window-server-level bookkeeping app-wide: hover/close tracking got confused and
//  the OS text-input caret rendered in the wrong place. Giving text entry its own ordinary,
//  unrelated window sidesteps all of that -- the notch panel's key status is never touched.
//

import AppKit
import SwiftUI

/// Reports the screen-space frame of the view it's attached to, using real AppKit view
/// geometry (`convert(_:to:)` + `window.convertToScreen`) rather than SwiftUI's `.global`
/// GeometryProxy coordinate space, whose orientation relative to a flipped/non-flipped
/// hosting view isn't something to guess at. This is correct regardless of that.
private struct ScreenFrameReader: NSViewRepresentable {
    let onChange: (CGRect) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onFrameChange = onChange
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onFrameChange = onChange
        nsView.reportFrame()
    }

    final class TrackingView: NSView {
        var onFrameChange: ((CGRect) -> Void)?
        private var settleTimer: Timer?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportFrame()
            scheduleSettleCorrections()
        }

        override func layout() {
            super.layout()
            reportFrame()
        }

        // The notch's tab-switch/open transition animates via SwiftUI transitions
        // (scale + opacity), which macOS implements as a Core Animation transform on the
        // presentation layer -- it doesn't trigger a fresh AppKit layout pass, so a frame
        // read at the moment this view appears can be mid-transition and stale. Rather than
        // guess the transition's exact duration, keep re-reading the real frame for a short
        // window after appearing so the backing panel snaps to the final, settled position.
        private func scheduleSettleCorrections() {
            settleTimer?.invalidate()
            var ticks = 0
            let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                self.reportFrame()
                ticks += 1
                if ticks >= 15 { timer.invalidate() }
            }
            RunLoop.main.add(timer, forMode: .common)
            settleTimer = timer
        }

        func reportFrame() {
            guard let window else { return }
            let frameInWindow = convert(bounds, to: nil)
            let frameOnScreen = window.convertToScreen(frameInWindow)
            onFrameChange?(frameOnScreen)
        }
    }
}

private final class InlineEntryPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        level = .mainMenu + 4
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct InlineEntryContentView: View {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .focused($isFocused)
            .onSubmit(onSubmit)
            .onExitCommand(perform: onCancel)
            .onAppear { isFocused = true }
    }
}

@MainActor
private final class InlineEntryCoordinator: ObservableObject {
    private var panel: InlineEntryPanel?
    @Published var isPresented = false

    func present(text: Binding<String>, placeholder: String, frame: CGRect, onSubmit: @escaping () -> Void) {
        let panel = self.panel ?? InlineEntryPanel()
        self.panel = panel
        let content = InlineEntryContentView(
            text: text,
            placeholder: placeholder,
            onSubmit: onSubmit,
            onCancel: { [weak self] in self?.dismiss() }
        )
        panel.contentView = NSHostingView(rootView: content)
        panel.setFrame(frame, display: false)
        panel.orderFront(nil)
        panel.makeKey()
        isPresented = true
    }

    func updateFrame(_ frame: CGRect) {
        guard let panel, panel.isVisible else { return }
        panel.setFrame(frame, display: false)
    }

    func dismiss() {
        panel?.resignKey()
        panel?.orderOut(nil)
        isPresented = false
    }
}

/// Drop-in replacement for a SwiftUI `TextField` that actually accepts keystrokes while
/// living inside the (never-key) notch panel. Visually it's just a rounded box showing
/// `text`; tapping it opens the backing panel positioned exactly on top, so typing looks
/// and feels inline even though the real first responder lives in a different window.
struct InlineTextField: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var notchCoordinator = BoringViewCoordinator.shared
    @Binding var text: String
    var placeholder: String = ""
    var autoFocus: Bool = false
    var onSubmit: () -> Void = {}

    @StateObject private var coordinator = InlineEntryCoordinator()
    @State private var screenFrame: CGRect = .zero

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.08))
            // Hidden while the backing panel is presented so there's only ever one
            // visible copy of the text, even if the overlay is a frame or two off
            // from settling into its final position.
            Text(text.isEmpty ? placeholder : text)
                .font(.caption)
                .foregroundColor(text.isEmpty ? Color(white: 0.5) : .white)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .opacity(coordinator.isPresented ? 0 : 1)
        }
        .background(
            ScreenFrameReader { frame in
                screenFrame = frame
                coordinator.updateFrame(frame)
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            present()
        }
        .onAppear {
            if autoFocus {
                // Give the ScreenFrameReader one layout pass to report a real frame
                // before we try to position the backing panel on top of it.
                DispatchQueue.main.async {
                    present()
                }
            }
        }
        .onDisappear {
            coordinator.dismiss()
        }
        // Dismiss the instant the notch starts closing rather than waiting for this
        // SwiftUI view's own onDisappear, which only fires after the close transition
        // finishes -- otherwise the (separate, real) panel visibly outlives the collapse.
        .onChange(of: vm.notchState) { _, state in
            if state == .closed {
                coordinator.dismiss()
            }
        }
        .onChange(of: notchCoordinator.currentView) { _, newView in
            if newView != .reminders {
                coordinator.dismiss()
            }
        }
    }

    private func present() {
        guard screenFrame != .zero else { return }
        coordinator.present(text: $text, placeholder: placeholder, frame: screenFrame, onSubmit: onSubmit)
    }
}
