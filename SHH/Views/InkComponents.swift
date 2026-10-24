import SwiftUI

// MARK: - Page frame

/// A Rock 3D title, then the subtitle with optional header actions beside it, above a scrolling
/// column capped at 680pt.
struct PageScaffold<Actions: View, Content: View>: View {
    let page: DashboardPage
    let actions: () -> Actions
    let content: () -> Content

    init(_ page: DashboardPage, @ViewBuilder actions: @escaping () -> Actions, @ViewBuilder content: @escaping () -> Content) {
        self.page = page
        self.actions = actions
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                DisplayText(page.title, size: 40, stroke: 1.1, lineHeight: 1.05)
                    .foregroundStyle(Ink.text)
                    .accessibilityAddTraits(.isHeader)
                HStack(alignment: .top, spacing: 28) {
                    Text(page.subtitle)
                        .font(.sans(14))
                        .lineSpacing(4)
                        .foregroundStyle(Ink.text2)
                        .frame(maxWidth: 480, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                    Spacer(minLength: 0)
                    HStack(spacing: 10) { actions() }
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 36)

            ScrollView {
                content()
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 44)
                    .padding(.top, 30)
                    .padding(.bottom, 72)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension PageScaffold where Actions == EmptyView {
    init(_ page: DashboardPage, @ViewBuilder content: @escaping () -> Content) {
        self.init(page, actions: { EmptyView() }, content: content)
    }
}

/// A section title in Rock 3D: Today, Transcription, Whisper.
struct SectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        DisplayText(title, size: 21, stroke: 0.6)
            .foregroundStyle(Ink.text)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Hairline list

/// Rows separated by inset hairlines, with a soft rounded fill on hover. Rows pad themselves.
/// The list bleeds 14pt into the page margin so row text lines up with the page title.
struct HairlineStack<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let isHoverable: (Item) -> Bool
    let row: (Item) -> Row
    @State private var hoveredID: Item.ID?

    init(_ items: [Item], isHoverable: @escaping (Item) -> Bool = { _ in true }, @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.isHoverable = isHoverable
        self.row = row
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let hoverable = isHoverable(item)
                row(item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        hoverable && hoveredID == item.id ? Ink.hover : .clear,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle()
                                .fill(Ink.hairline)
                                .frame(height: 1)
                                .padding(.horizontal, 14)
                                .opacity(hidesDivider(above: index) ? 0 : 1)
                        }
                    }
                    .onHover { inside in
                        if inside {
                            hoveredID = hoverable ? item.id : nil
                        } else if hoveredID == item.id {
                            hoveredID = nil
                        }
                    }
            }
        }
        .padding(.horizontal, -14)
        .animation(.easeOut(duration: 0.15), value: hoveredID)
    }

    private func hidesDivider(above index: Int) -> Bool {
        guard let hoveredID else { return false }
        return items[index].id == hoveredID || items[index - 1].id == hoveredID
    }
}

extension View {
    /// The standard padding of a hairline list row.
    func listRowPadding() -> some View {
        padding(.vertical, 16).padding(.horizontal, 14)
    }
}

// MARK: - Buttons

/// Pills: ink for the primary action, a soft fill for secondary ones, bare text for the rest.
struct InkButtonStyle: ButtonStyle {
    enum Kind { case primary, ghost, plain }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind)
    }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.sans(13.5, .semibold))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .plain ? 12 : 15)
                .frame(height: 32)
                .background(background, in: Capsule())
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }

        private var foreground: Color {
            switch kind {
            case .primary: isEnabled ? Ink.paper : Ink.text3
            case .ghost: isEnabled ? Ink.text : Ink.text3
            case .plain: isHovered && isEnabled ? Ink.text : Ink.text2
            }
        }

        private var background: Color {
            let hovered = isHovered && isEnabled
            switch kind {
            case .primary: return isEnabled ? (hovered ? Ink.inkSoft : Ink.ink) : Ink.fill
            case .ghost: return hovered ? Ink.fillHover : Ink.fill
            case .plain: return hovered ? Ink.fill : .clear
            }
        }
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    static func ink(_ kind: InkButtonStyle.Kind) -> InkButtonStyle { .init(kind: kind) }
}

/// A 30pt round glyph button.
struct InkIconButtonStyle: ButtonStyle {
    var rest: Color = Ink.text2

    func makeBody(configuration: Configuration) -> some View {
        IconButton(configuration: configuration, rest: rest)
    }

    private struct IconButton: View {
        let configuration: ButtonStyleConfiguration
        let rest: Color
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let hovered = isHovered && isEnabled
            configuration.label
                .foregroundStyle(hovered ? Ink.text : rest)
                .frame(width: 30, height: 30)
                .background(hovered ? Ink.fillHover : .clear, in: Circle())
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { isHovered = $0 }
        }
    }
}

/// An underlined text link; the underline darkens to ink on hover.
struct TextLink: View {
    let label: Text
    var color: Color = Ink.text
    let action: () -> Void
    @State private var isHovered = false

    init(_ title: String, color: Color = Ink.text, action: @escaping () -> Void) {
        self.init(label: Text(title), color: color, action: action)
    }

    init(label: Text, color: Color = Ink.text, action: @escaping () -> Void) {
        self.label = label
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            label
                .underline(true, color: isHovered ? Ink.ink : Ink.off)
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Menus

/// The always-visible "…" on a row. Give the row the same items with `.contextMenu`
/// so right-click works too.
struct RowMenuButton<Items: View>: View {
    let label: String
    let items: () -> Items
    @State private var isHovered = false

    init(_ label: String, @ViewBuilder items: @escaping () -> Items) {
        self.label = label
        self.items = items
    }

    var body: some View {
        Menu(content: items) {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isHovered ? Ink.text : Ink.text3)
                .frame(width: 30, height: 30)
                .background(isHovered ? Ink.fillHover : .clear, in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help("More")
        .accessibilityLabel("Actions for \(label)")
    }
}

/// A filled pill pop-up button: the current value and a chevron.
struct InkMenu<Content: View>: View {
    let title: String
    let width: CGFloat
    let content: () -> Content
    @State private var isHovered = false

    init(_ title: String, width: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.width = width
        self.content = content
    }

    var body: some View {
        Menu(content: content) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.sans(13.5, .medium))
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Ink.text2)
            }
            .padding(.leading, 14)
            .padding(.trailing, 11)
            .frame(width: width, height: 32)
            .background(isHovered ? Ink.fillHover : Ink.fill, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help(title)
    }
}

// MARK: - Toggles

/// Ink when on. The knob stretches like a drop as it slides across.
struct InkSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? Ink.ink : Ink.off)
                .frame(width: 40, height: 24)
                .overlay { Knob(isOn: configuration.isOn) }
                .contentShape(Capsule())
                .animation(.easeOut(duration: 0.2), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }

    private struct Knob: View {
        let isOn: Bool

        var body: some View {
            Capsule()
                .fill(Ink.paper)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                .keyframeAnimator(initialValue: CGFloat(0), trigger: isOn) { knob, stretch in
                    knob.frame(width: 18 + stretch, height: 18)
                } keyframes: { _ in
                    CubicKeyframe(9, duration: 0.1)
                    CubicKeyframe(0, duration: 0.16)
                }
                .offset(x: isOn ? 8 : -8)
                .animation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.26), value: isOn)
        }
    }
}

extension ToggleStyle where Self == InkSwitchStyle {
    static var inkSwitch: InkSwitchStyle { .init() }
}

/// An ink ring that fills into an ink disc with a paper dot.
struct RadioMark: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(Ink.off, lineWidth: 2)
            Circle()
                .fill(Ink.ink)
                .overlay { Circle().fill(Ink.paper).frame(width: 6, height: 6) }
                .scaleEffect(isOn ? 1 : 0.01)
        }
        .frame(width: 18, height: 18)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isOn)
        .accessibilityHidden(true)
    }
}

// MARK: - Fields

/// A filled pill; focus turns it paper with an ink ring.
struct InkFieldStyle<S: InsettableShape>: ViewModifier {
    let isFocused: Bool
    let shape: S
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isFocused ? Ink.paper : isHovered ? Ink.fillHover : Ink.fill, in: shape)
            .overlay { shape.strokeBorder(Ink.ink, lineWidth: isFocused ? 2 : 0) }
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

extension View {
    func inkField(focused: Bool) -> some View {
        textFieldStyle(.plain)
            .font(.sans(13.5))
            .foregroundStyle(Ink.text)
            .focusEffectDisabled()
            .padding(.horizontal, 15)
            .frame(height: 38)
            .modifier(InkFieldStyle(isFocused: focused, shape: Capsule()))
    }
}

/// A single-line field with its own placeholder: macOS ignores a `prompt`'s color.
struct InkTextField<Field: Hashable>: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    let focus: FocusState<Field?>.Binding
    let field: Field

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text, prompt: Text(""))
            } else {
                TextField(placeholder, text: $text, prompt: Text(""))
            }
        }
        .focused(focus, equals: field)
        .overlay(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.sans(13.5))
                    .foregroundStyle(Ink.text3)
                    .lineLimit(1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .inkField(focused: focus.wrappedValue == field)
    }
}

/// A multi-line field with a placeholder, styled like `inkField` with softer corners.
struct InkTextEditor<Field: Hashable>: View {
    @Binding var text: String
    let placeholder: String
    let focus: FocusState<Field?>.Binding
    let field: Field

    var body: some View {
        TextEditor(text: $text)
            .font(.sans(13.5))
            .lineSpacing(4)
            .foregroundStyle(Ink.text)
            .scrollContentBackground(.hidden)
            .focused(focus, equals: field)
            .focusEffectDisabled()
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .frame(minHeight: 104)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.sans(13.5))
                        .foregroundStyle(Ink.text3)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .allowsHitTesting(false)
                }
            }
            .modifier(InkFieldStyle(
                isFocused: focus.wrappedValue == field,
                shape: RoundedRectangle(cornerRadius: 18, style: .continuous)
            ))
    }
}

/// A label above a control.
struct FieldBlock<Content: View>: View {
    let label: String
    var isOptional = false
    let content: () -> Content

    init(_ label: String, isOptional: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.isOptional = isOptional
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(label).font(.sans(12.5, .semibold)).foregroundStyle(Ink.text)
                if isOptional {
                    Text("optional").font(.sans(12.5)).foregroundStyle(Ink.text3)
                }
            }
            content()
        }
    }
}

// MARK: - Settings rows

struct SettingsGroup<Content: View>: View {
    let title: String
    let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(title)
            VStack(alignment: .leading, spacing: 0) { content() }
        }
    }
}

/// A label and description with a control on the right. Rows after the first draw a hairline above.
struct SettingRow<Control: View>: View {
    let label: String
    var description: String?
    var isWarning = false
    var isFirst = false
    let control: () -> Control

    init(
        _ label: String,
        description: String? = nil,
        isWarning: Bool = false,
        isFirst: Bool = false,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.label = label
        self.description = description
        self.isWarning = isWarning
        self.isFirst = isFirst
        self.control = control
    }

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.sans(15, .medium)).foregroundStyle(Ink.text)
                if let description {
                    Text(description)
                        .font(.sans(14, isWarning ? .medium : .regular))
                        .lineSpacing(4)
                        .foregroundStyle(isWarning ? Ink.text : Ink.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) { control() }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle().fill(Ink.hairline).frame(height: 1)
            }
        }
    }
}

// MARK: - Small pieces

/// A key cap in ink.
struct Kbd: View {
    let key: String
    var isCompact = false

    init(_ key: String, isCompact: Bool = false) {
        self.key = key
        self.isCompact = isCompact
    }

    var body: some View {
        Text(key)
            .font(.inkMono(isCompact ? 10.5 : 11.5, .semibold))
            .foregroundStyle(Ink.onInk)
            .padding(.horizontal, isCompact ? 4 : 6)
            .frame(minWidth: isCompact ? 18 : 22, minHeight: isCompact ? 17 : 21)
            .background(Ink.ink, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// "● In use", in ink.
struct DotLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Ink.ink).frame(width: 7, height: 7)
            Text(text).fontWeight(.semibold)
        }
        .foregroundStyle(Ink.text)
    }
}

/// An inline "are you sure?" line: message, Cancel (esc) and a primary confirm.
struct InlineConfirm: View {
    let message: Text
    let confirmTitle: String
    var cancelTitle = "Cancel"
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            message
                .font(.sans(14))
                .foregroundStyle(Ink.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(cancelTitle, action: onCancel)
                .buttonStyle(.ink(.plain))
                .keyboardShortcut(.cancelAction)
            Button(confirmTitle, action: onConfirm)
                .buttonStyle(.ink(.primary))
        }
    }
}

/// A centred message for an empty page, optionally under the mark.
struct EmptyState<Accessory: View>: View {
    let title: String
    var showsMark = false
    let accessory: () -> Accessory

    init(_ title: String, showsMark: Bool = false, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.showsMark = showsMark
        self.accessory = accessory
    }

    var body: some View {
        VStack(spacing: 6) {
            if showsMark {
                InkMarkView(spraysOnHover: true)
                    .frame(width: 92, height: 105)
                    .foregroundStyle(Ink.ink)
                    .padding(.bottom, 14)
            }
            DisplayText(title, size: 21, stroke: 0.6)
                .foregroundStyle(Ink.text)
            accessory()
        }
        .font(.sans(14))
        .foregroundStyle(Ink.text2)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 44)
        .padding(.bottom, 24)
    }
}

/// A small filled pill that turns ink on hover, like a row's "Download".
struct InkChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration)
    }

    private struct Chip: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let hovered = isHovered && isEnabled
            configuration.label
                .font(.sans(12.5, .semibold))
                .foregroundStyle(hovered ? Ink.paper : Ink.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(hovered ? Ink.ink : Ink.fill, in: Capsule())
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.15), value: hovered)
        }
    }
}

private struct HoverFill: ViewModifier {
    let cornerRadius: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? Ink.hover : .clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

extension View {
    /// A soft fill while the pointer is over the view.
    func hoverFill(cornerRadius: CGFloat = 20) -> some View {
        modifier(HoverFill(cornerRadius: cornerRadius))
    }
}
