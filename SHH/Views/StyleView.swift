import SwiftUI
import SwiftData

struct StyleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Style.name) private var styles: [Style]
    @State private var showCreateSheet = false
    @State private var editingStyle: Style?
    @State private var isAddHovered = false

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
        HStack(alignment: .center) {
            Text("Styles")
                .font(Font.appHeadline)
                .fontWeight(.bold)
                .foregroundStyle(Color.appForeground)
                .alignmentGuide(VerticalAlignment.center) { d in
                    d[.firstTextBaseline] / 2
                }
            Spacer()
            Button {
                showCreateSheet = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(Font.appBody)
                    .foregroundStyle(isAddHovered ? Color.appError : Color.appForeground.opacity(0.8))
            }
            .buttonStyle(.plain)
            .onHover { isAddHovered = $0 }
            .help("New Style")
        }
        .padding(.horizontal, 24)
        .frame(height: 52)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "paintbrush")
                .font(.system(size: 36))
                .foregroundStyle(Color.appForeground.opacity(0.25))
            Text("No Styles")
                .font(Font.appTitle3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appForeground)
            Text("Create a style to transform your dictated text with AI.")
                .font(Font.appBody)
                .foregroundStyle(Color.appForeground.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @State private var isRowHovered = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(style.name)
                        .font(Font.appBody)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.appForeground)
                    if style.isActive {
                        Text("Active")
                            .font(Font.appCaption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.appError)
                            .clipShape(Capsule())
                    }
                }
                Text(style.systemPrompt)
                    .font(Font.appCaption)
                    .foregroundStyle(Color.appForeground.opacity(0.6))
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { style.isActive },
                set: { _ in onToggleActive() }
            ))
            .toggleStyle(AppToggleStyle())
            .labelsHidden()
        }
        .padding(20)
        .background(
            isRowHovered
                ? Color.appForeground.opacity(0.08)
                : Color.appForeground.opacity(0.05)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
             RoundedRectangle(cornerRadius: 8)
                 .stroke(
                    Color.appForeground.opacity(0.1),
                    lineWidth: 1
                 )
        )
        .listRowSeparator(.hidden)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isRowHovered = $0 }
        .onTapGesture { onEdit() }
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
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
    @FocusState private var focusedField: StyleField?
    private enum StyleField: Hashable { case name, systemPrompt }

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
            // Sheet header
            HStack {
                Text(isEditing ? "Edit Style" : "New Style")
                    .font(Font.appTitle3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.appForeground)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(Font.appBody)
                        .foregroundStyle(Color.appForeground.opacity(0.6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .frame(height: 52)

            Divider()

            // Form body
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(Font.appSubheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appForeground.opacity(0.7))
                        TextField("", text: $name)
                            .focused($focusedField, equals: .name)
                            .font(Font.appBody)
                            .textFieldStyle(.plain)
                            .foregroundStyle(Color.appForeground)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.appForeground.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.appForeground.opacity(0.12), lineWidth: 1)
                            )
                    }

                    // System prompt field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("System Prompt")
                            .font(Font.appSubheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appForeground.opacity(0.7))
                        TextEditor(text: $systemPrompt)
                            .focused($focusedField, equals: .systemPrompt)
                            .font(Font.appBody)
                            .foregroundStyle(Color.appForeground)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 140)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.appForeground.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.appForeground.opacity(0.12), lineWidth: 1)
                            )
                    }
                }
                .padding(24)
            }

            Divider()

            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .font(Font.appBody)
                    .foregroundStyle(Color.appForeground.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.appForeground.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)

                Spacer()

                Button(isEditing ? "Save" : "Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .font(Font.appBody)
                    .fontWeight(.semibold)
                    .foregroundStyle(isValid ? .white : Color.appForeground.opacity(0.4))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isValid ? Color.appError : Color.appForeground.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .buttonStyle(.plain)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 460)
        .background(Color.appBackground)
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
