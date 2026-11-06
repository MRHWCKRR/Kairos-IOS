import SwiftUI

struct KairosChecklistEditor: View {
    @Binding var items: [KairosChecklistItem]
    let allowsCompletion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Checklist", sharedIcon: "checklist").font(.subheadline.weight(.semibold))
            if !allowsCompletion {
                Text("These are recurring series steps. Track each occurrence from Calendar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach($items) { $item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button { item.completed.toggle() } label: {
                            KairosIcon(item.completed ? "checkmark.circle.fill" : "circle")
                        }
                        .disabled(!allowsCompletion && !item.completed)
                        .accessibilityLabel(item.completed ? "Mark step incomplete" : "Complete step")
                        TextField("Step title", text: $item.title, axis: .vertical)
                            .accessibilityLabel("Checklist step title")
                        Button(role: .destructive) { items.removeAll { $0.id == item.id } } label: {
                            KairosIcon("trash")
                        }.accessibilityLabel("Remove step")
                    }
                    HStack {
                        Button { move(item.id, by: -1) } label: { Label("Up", sharedIcon: "arrow.up") }
                            .disabled(items.first?.id == item.id)
                        Button { move(item.id, by: 1) } label: { Label("Down", sharedIcon: "arrow.down") }
                            .disabled(items.last?.id == item.id)
                    }.font(.caption)
                    Divider()
                }
            }
            Button {
                items.append(KairosChecklistItem(id: "check-\(UUID().uuidString)", title: "", completed: false))
            } label: { Label("Add step", sharedIcon: "plus") }
                .disabled(items.count >= 100)
            Text("\(items.count)/100 steps · 180 characters per step")
                .font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .padding(18).kairosCard(cornerRadius: 22)
    }

    private func move(_ id: String, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }), items.indices.contains(index + offset) else { return }
        items.swapAt(index, index + offset)
    }
}

