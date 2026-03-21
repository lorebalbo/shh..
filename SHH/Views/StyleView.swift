import SwiftUI
import SwiftData

struct StyleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Style.name) private var styles: [Style]
    @State private var showCreateSheet = false
    @State private var editingStyle: Style?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if styles.isEmpty {
                emptyState
            } else {
                styleList
            }
        }
        .background(Color.appBackground)
        .sheet(isPresented: $showCreateSheet) {
            StyleFormSheet(mode: .create)
        }
        .sheet(item: $editingStyle) { style in
            StyleFormSheet(mode: .edit(style))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Styles")
                .font(Font.appLargeTitle)
                .fontWeight(.bold)
                .foregroundStyle(Color.appForeground)
            Spacer()
            Button {
                showCreateSheet = true
            } label: {
                Label("New Style", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Styles", systemImage: "paintbrush")
        } description: {
            Text("Create a style to transform your dictated text with AI.")
        } actions: {
            Button("Create Style") {
                showCreateSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - List

    private var styleList: some View {
        List {
            ForEach(styles) { style in
                StyleRow(
                    style: style,
                    onToggleActive: { toggleActive(style) },
                    onEdit: { editingStyle = style },
                    onDelete: { deleteStyle(style) }
                )
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }

    // MARK: - Actions

    private func toggleActive(_ style: Style) {
        if style.isActive {
            style.isActive = false
        } else {
            try? style.activate(in: modelContext)
        }
    }

    private func deleteStyle(_ style: Style) {
        modelContext.delete(style)
    }
}

// MARK: - Style Row

private struct StyleRow: View {
    let style: Style
    let onToggleActive: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleActive) {
                Image(systemName: style.isActive ? "checkmark.circle.fill" : "circle")
                    .font(Font.appTitle3)
                    .foregroundStyle(style.isActive ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(style.isActive ? "Deactivate style" : "Activate style")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(style.name)
                        .fontWeight(.medium)
                    if style.isActive {
                        Text("Active")
                            .font(Font.appCaption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }
                Text(style.systemPrompt)
                    .font(Font.appCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit style")

            Button(action: { showDeleteConfirmation = true }) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Delete style")
        }
        .padding(12)
        .background(Color.appForeground.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
             RoundedRectangle(cornerRadius: 8)
                 .stroke(Color.appForeground.opacity(0.1), lineWidth: 1)
        )
        .listRowSeparator(.hidden)
        .padding(.vertical, 2)
        .confirmationDialog("Delete Style", isPresented: $showDeleteConfirmation) {
            Button("Delete \"\(style.name)\"", role: .destructive, action: onDelete)
        } message: {
            Text("Are you sure you want to delete this style? This action cannot be undone.")
        }
    }
}

// MARK: - Style Form Sheet

private struct StyleFormSheet: View {
    enum Mode: Identifiable {
        case create
        case edit(Style)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let style): style.id.uuidString
            }
        }
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var systemPrompt: String = ""

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isEditing ? "Edit Style" : "New Style")
                .font(Font.appHeadline)
                .padding(.top, 16)

            Form {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    Text("System Prompt")
                        .font(Font.appSubheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $systemPrompt)
                        .font(Font.appBody)
                        .frame(minHeight: 120)
                        .border(.separator)
                }
            }
            .padding()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isEditing ? "Save" : "Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .frame(width: 420)
        .onAppear {
            if case .edit(let style) = mode {
                name = style.name
                systemPrompt = style.systemPrompt
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create:
            let style = Style(name: trimmedName, systemPrompt: trimmedPrompt)
            modelContext.insert(style)
        case .edit(let style):
            style.name = trimmedName
            style.systemPrompt = trimmedPrompt
        }
        dismiss()
    }
}
