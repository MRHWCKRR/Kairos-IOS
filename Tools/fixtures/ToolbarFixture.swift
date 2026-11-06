import SwiftUI
import UIKit

// This app compiles the production toolbar helper and asset catalog directly.
// It has no Firebase, authentication, repository, or network dependencies.
@main
struct ToolbarFixtureApp: App {
    var body: some Scene {
        WindowGroup {
            ToolbarFixture()
                .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--accessibility") ? .accessibility5 : .large)
        }
    }
}

private struct ToolbarFixture: View {
    private let screen = ProcessInfo.processInfo.arguments.contains("--backlog") ? "backlog" : "chats"
    private var isBacklog: Bool { screen == "backlog" }

    var body: some View {
        NavigationStack {
            Text(isBacklog ? "Calendar toolbar regression fixture" : "AI Chats toolbar regression fixture")
                .navigationTitle(isBacklog ? "Calendar" : "AI Helper")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        KairosToolbarButton(isBacklog ? "Backlog" : "Chats and projects", sharedIcon: isBacklog ? "tray" : "sidebar.left") { }
                            .background(ToolbarBoundsProbe(screen: screen, name: "leading"))
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        KairosToolbarButton(isBacklog ? "Agenda" : "New chat", sharedIcon: isBacklog ? "list.bullet" : "square.and.pencil") { }
                            .disabled(ProcessInfo.processInfo.arguments.contains("--disabled"))
                            .background(ToolbarBoundsProbe(screen: screen, name: "trailing"))
                        Menu { Button("Fixture action") { } } label: {
                            KairosIcon(isBacklog ? "line.3.horizontal.decrease" : "ellipsis")
                        }
                        .accessibilityLabel("More options")
                        if isBacklog {
                            Menu { Button("Task") { } } label: { KairosIcon("plus") }
                                .accessibilityLabel("Add to schedule")
                        }
                    }
                }
        }
    }
}

/// Measure after UIKit has laid out the *real navigation bar*, including its
/// native button wrapper. Measuring only an isolated SwiftUI label would miss
/// the wide-pill regression. The full ancestry is retained for CI diagnostics.
private struct ToolbarBoundsProbe: UIViewRepresentable {
    let screen: String
    let name: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak view] in
            guard let view, let window = view.window else { return }
            var ancestors: [[String: Any]] = []
            var parent = view.superview
            var nativeButton: CGRect?
            while let current = parent {
                let className = NSStringFromClass(type(of: current))
                let rect = current.convert(current.bounds, to: window)
                ancestors.append(["class": className, "width": rect.width, "height": rect.height])
                // iOS 26 wraps each control in PlatterItemView. Its parent
                // glass platter can legitimately group multiple controls.
                if className.contains("ButtonBarButton") || className.contains("NavigationBarPlatterItemView") {
                    nativeButton = rect
                }
                parent = current.superview
            }
            let labelRect = view.convert(view.bounds, to: window)
            let expectedTitle = screen == "backlog" ? "Calendar" : "AI Helper"
            func findTitle(in root: UIView) -> UILabel? {
                if let label = root as? UILabel, label.text == expectedTitle { return label }
                return root.subviews.lazy.compactMap { findTitle(in: $0) }.first
            }
            let title = findTitle(in: window)
            let titleRect = title.map { $0.convert($0.bounds, to: window) } ?? .zero
            let report: [String: Any] = [
                "screen": screen, "name": name,
                "labelWidth": labelRect.width, "labelHeight": labelRect.height,
                "nativeWidth": nativeButton?.width ?? -1,
                "nativeHeight": nativeButton?.height ?? -1,
                "nativeX": nativeButton?.minX ?? -1,
                "x": labelRect.minX, "y": labelRect.minY,
                "windowWidth": window.bounds.width, "ancestors": ancestors,
                "titleWidth": titleRect.width, "titleX": titleRect.minX,
                "titleVisible": title.map { !$0.isHidden && $0.alpha > 0 && titleRect.width > 0 } ?? false
            ]
            let destination = URL.documentsDirectory.appendingPathComponent("\(name).json")
            do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: destination) }
            catch { print("Could not save toolbar measurement: \(error)") }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) { }
}
