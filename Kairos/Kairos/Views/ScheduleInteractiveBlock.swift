import SwiftUI

enum ScheduleTouchMode: Equatable { case move, resize }

struct ScheduleInteractiveBlock: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    private func displayClock(_ minute: Int) -> String { KairosTimeDisplay.clock(minute, format: profileRepo.accessibilitySettings?.timeFormat ?? "12") }
    let title: String
    let start: Int
    let end: Int
    let recurring: Bool
    let completed: Bool
    let editable: Bool
    let active: Bool
    let busy: Bool
    let open: () -> Void
    let editDetails: () -> Void
    let begin: (ScheduleTouchMode) -> Bool
    let change: (ScheduleTouchMode, CGSize, CGPoint) -> Void
    let finish: () -> Void
    let cancel: () -> Void
    let adjust: (ScheduleTouchMode, Int) -> Void

    @GestureState private var moving = false
    @GestureState private var resizing = false
    @State private var operation: ScheduleTouchMode?
    @State private var blocked = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.caption.weight(.semibold)).lineLimit(3).strikethrough(completed)
                    Text("\(displayClock(start))–\(displayClock(end))").font(.system(size: 10)).monospacedDigit().lineLimit(1)
                    if recurring { KairosIcon("repeat", size: 9) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(6)
            }
            .buttonStyle(.plain)
            .highPriorityGesture(moveGesture, including: editable && !busy ? .all : .subviews)
            if editable {
                Button(action: editDetails) {
                    KairosIcon("arrow.up.and.down", size: 11)
                        .frame(width: 44).frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Resize \(title)")
                .highPriorityGesture(resizeGesture, including: busy ? .subviews : .all)
            }
        }
        .background(KairosColors.accent.opacity(completed ? 0.08 : 0.16), in: RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(KairosColors.accent.opacity(active ? 1 : 0.2), lineWidth: active ? 2 : 0.5) }
        .opacity(active ? 0.35 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(displayClock(start)) to \(displayClock(end))\(completed ? ", completed" : "")")
        .accessibilityHint(editable ? "Hold to move. Use the resize handle to change the end time." : "Open details to edit this task.")
        .accessibilityAction(named: "Move five minutes earlier") { if editable && !busy { adjust(.move, -5) } }
        .accessibilityAction(named: "Move five minutes later") { if editable && !busy { adjust(.move, 5) } }
        .accessibilityAction(named: "Extend five minutes") { if editable && !busy { adjust(.resize, 5) } }
        .accessibilityAction(named: "Shorten five minutes") { if editable && !busy { adjust(.resize, -5) } }
        .onChange(of: moving) { _, value in if !value { settleCancellation() } }
        .onChange(of: resizing) { _, value in if !value { settleCancellation() } }
        .onDisappear { if operation != nil { operation = nil; cancel() } }
    }

    private var moveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($moving) { value, active, _ in if case .second(true, _) = value { active = true } }
            .onChanged { value in
                if case .second(true, let drag) = value {
                    beginGesture(.move)
                    if operation == .move, let drag { change(.move, drag.translation, drag.location) }
                }
            }
            .onEnded { _ in endGesture() }
    }
    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .updating($resizing) { _, active, _ in active = true }
            .onChanged { value in beginGesture(.resize); if operation == .resize { change(.resize, value.translation, value.location) } }
            .onEnded { _ in endGesture() }
    }
    private func beginGesture(_ mode: ScheduleTouchMode) {
        guard operation == nil, !blocked else { return }
        if begin(mode) { operation = mode } else { blocked = true }
    }
    private func endGesture() {
        let hadOperation = operation != nil
        operation = nil; blocked = false
        if hadOperation { finish() }
    }
    private func settleCancellation() {
        // GestureState also resets before a successful onEnded callback. Yield
        // once so only actual cancellation (without onEnded) rolls back preview.
        Task { @MainActor in
            await Task.yield()
            if operation != nil, !moving, !resizing { operation = nil; cancel() }
            if !moving && !resizing { blocked = false }
        }
    }
}

struct ScheduleColumnFrames: PreferenceKey {
    nonisolated static let defaultValue: [String: CGRect] = [:]
    nonisolated static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { _, new in new } }
}
struct ScheduleViewportFrame: PreferenceKey {
    nonisolated static let defaultValue: CGRect = .zero
    nonisolated static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

