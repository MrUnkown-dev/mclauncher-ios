import SwiftUI

/// Live log console. Reads the same buffer the launcher appends to.
struct ConsoleView: View {
    let lines: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(color(for: line))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(10)
                }
                .background(Color.black)
                .onChange(of: lines.count) { _, newValue in
                    withAnimation { proxy.scrollTo(newValue - 1, anchor: .bottom) }
                }
            }
            .navigationTitle("Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func color(for line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("exception") || lower.contains("fatal") { return .red }
        if lower.contains("warn") { return .yellow }
        if lower.contains("[mcl]") { return .cyan }
        return .green.opacity(0.85)
    }
}
