import SwiftData
import SwiftUI

struct StylesView: View {
    @Environment(DashboardModel.self) private var dashboard
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Style.name) private var styles: [Style]
    @State private var editing: EditTarget?
    @State private var draftName = ""
    @State private var draftPrompt = ""
    @State private var confirmingDelete: UUID?
    @FocusState private var focusedField: DraftField?

    private enum EditTarget: Equatable {
        case new
        case existing(UUID)
    }

    private enum DraftField: Hashable {
        case name
        case prompt
    }

    private enum Row: Identifiable {
        case editor
        case style(Style)
        case noStyle

        var id: String {
            switch self {
            case .editor: "editor"
            case .style(let style): style.id.uuidString
            case .noStyle: "none"
            }
        }
    }

    private var rows: [Row] {
        var rows: [Row] = editing == .new ? [.editor] : []
        rows += styles.map { editing == .existing($0.id) ? .editor : .style($0) }
        rows.append(.noStyle)
        return rows
    }

    private var isDraftValid: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        PageScaffold(.styles) {
            Button(action: startNew) {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    Text("New style")
                    Text("⌘N")
                        .font(.sans(12))
                        .foregroundStyle(Ink.text3)
                        .padding(.leading, 4)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.ink(.ghost))
            .disabled(editing != nil)
        } content: {
            HairlineStack(rows, isHoverable: { row in
                if case .editor = row { return false }
                return true
            }) { row in
                switch row {
                case .editor: editor
                case .style(let style): styleRow(style)
                case .noStyle: noStyleRow
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Active style")
        }
        .onAppear { startNewIfRequested() }
        .onChange(of: dashboard.wantsNewStyle) { startNewIfRequested() }
    }

    // MARK: - Rows

    private func styleRow(_ style: Style) -> some View {
        let isConfirming = confirmingDelete == style.id
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                pick(isOn: style.isActive, name: style.name, description: style.systemPrompt) {
                    activate(style)
                }
                if isConfirming {
                    Color.clear.frame(width: 30, height: 30)
                } else {
                    RowMenuButton(style.name) { styleMenuItems(style) }
                        .padding(.top, -4)
                        .padding(.trailing, -6)
                }
            }
            if isConfirming {
                InlineConfirm(
                    message: Text("Delete “\(style.name)”? This can't be undone.").fontWeight(.medium).foregroundColor(Ink.text),
                    confirmTitle: "Delete",
                    onCancel: { confirmingDelete = nil },
                    onConfirm: { delete(style) }
                )
                .padding(.leading, 32)
            }
        }
        .listRowPadding()
        .contentShape(Rectangle())
        .contextMenu {
            if !isConfirming { styleMenuItems(style) }
        }
    }

    private var noStyleRow: some View {
        let isOn = !styles.contains(where: \.isActive)
        return HStack(alignment: .top, spacing: 12) {
            pick(isOn: isOn, name: "No style", description: "Copy the transcript exactly as it was heard.") {
                activate(nil)
            }
            Color.clear.frame(width: 30, height: 30)
        }
        .listRowPadding()
    }

    private func pick(isOn: Bool, name: String, description: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                RadioMark(isOn: isOn)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.sans(15, .semibold))
                        .foregroundStyle(Ink.text)
                    Text(description)
                        .font(.sans(14))
                        .lineSpacing(4)
                        .foregroundStyle(Ink.text2)
                        .lineLimit(2)
                        .frame(maxWidth: 520, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func styleMenuItems(_ style: Style) -> some View {
        if style.isActive {
            Button { activate(nil) } label: { Label("Stop using", systemImage: "xmark.circle") }
        } else {
            Button { activate(style) } label: { Label("Use", systemImage: "smallcircle.filled.circle") }
        }
        Button { startEditing(style) } label: { Label("Edit", systemImage: "pencil") }
        Divider()
        Button(role: .destructive) {
            confirmingDelete = style.id
        } label: {
            Label("Delete…", systemImage: "trash")
        }
    }

    // MARK: - Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            FieldBlock("Name") {
                InkTextField(placeholder: "Meeting notes", text: $draftName, focus: $focusedField, field: .name)
                    .onSubmit { focusedField = .prompt }
            }
            FieldBlock("Instructions") {
                InkTextEditor(
                    text: $draftPrompt,
                    placeholder: "Tell the model how to rewrite your transcript.",
                    focus: $focusedField,
                    field: .prompt
                )
            }
            HStack(spacing: 6) {
                Text("⌘↩ save · esc cancel")
                    .font(.sans(12))
                    .foregroundStyle(Ink.text3)
                Spacer(minLength: 0)
                Button("Cancel", action: cancelEditing)
                    .buttonStyle(.ink(.plain))
                    .keyboardShortcut(.cancelAction)
                Button(editing == .new ? "Create style" : "Save", action: save)
                    .buttonStyle(.ink(.primary))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!isDraftValid)
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 20)
        .padding(.leading, 46)
        .padding(.trailing, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(editing == .new ? "New style" : "Edit \(draftName)")
    }

    // MARK: - Actions

    private func startNewIfRequested() {
        guard dashboard.wantsNewStyle else { return }
        dashboard.wantsNewStyle = false
        startNew()
    }

    private func startNew() {
        guard editing == nil else { return }
        draftName = ""
        draftPrompt = ""
        confirmingDelete = nil
        editing = .new
        DispatchQueue.main.async { focusedField = .name }
    }

    private func startEditing(_ style: Style) {
        draftName = style.name
        draftPrompt = style.systemPrompt
        confirmingDelete = nil
        editing = .existing(style.id)
        DispatchQueue.main.async { focusedField = .name }
    }

    private func cancelEditing() {
        editing = nil
        focusedField = nil
    }

    private func save() {
        guard isDraftValid, let editing else { return }
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        switch editing {
        case .new:
            modelContext.insert(Style(name: name, systemPrompt: prompt))
        case .existing(let id):
            guard let style = styles.first(where: { $0.id == id }) else { break }
            style.name = name
            style.systemPrompt = prompt
        }
        self.editing = nil
        focusedField = nil
        saveStyleChanges()
    }

    /// Makes `style` the only active style, or turns styles off with nil.
    private func activate(_ style: Style?) {
        confirmingDelete = nil
        if let style {
            guard !style.isActive else { return }
            try? style.activate(in: modelContext)
        } else {
            for active in styles where active.isActive { active.isActive = false }
        }
        saveStyleChanges()
    }

    private func delete(_ style: Style) {
        confirmingDelete = nil
        modelContext.delete(style)
        saveStyleChanges()
    }

    private func saveStyleChanges() {
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .shhStylesDidChange, object: nil)
        } catch {
        }
    }
}
