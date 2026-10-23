import SwiftUI

// MARK: - Page frame

/// Title, optional header actions and a subtitle, above a scrolling column capped at 680pt.
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 16) {
                    Text(page.title)
                        .font(.inter(27, .semibold))
                        .tracking(-0.54)
                        .foregroundStyle(Graphite.text)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    HStack(spacing: 10) { actions() }
                }
                .frame(minHeight: 34)
                Text(page.subtitle)
                    .font(.inter(14))
                    .lineSpacing(4)
                    .foregroundStyle(Graphite.text2)
                    .frame(maxWidth: 540, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 44)
            .padding(.top, 38)

            ScrollView {
                content()
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 44)
                    .padding(.top, 28)
                    .padding(.bottom, 64)
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

// MARK: - Hairline list

/// Rows separated by inset hairlines, with a soft hover fill. Rows pad themselves.
/// The list bleeds 12pt into the page margin so row text lines up with the page title.
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
                        hoverable && hoveredID == item.id ? Graphite.hover : .clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay(alignment: .top) {
                        if index > 0 {
                            Rectangle()
                                .fill(Graphite.hairline)
                                .frame(height: 1)
                                .padding(.horizontal, 12)
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
        .padding(.horizontal, -12)
        .animation(.easeOut(duration: 0.12), value: hoveredID)
    }

    private func hidesDivider(above index: Int) -> Bool {
        guard let hoveredID else { return false }
        return items[index].id == hoveredID || items[index - 1].id == hoveredID
    }
}

extension View {
    /// The standard padding of a hairline list row.
    func listRowPadding() -> some View {
        padding(.vertical, 16).padding(.horizontal, 12)
    }
}

// MARK: - Buttons

struct GraphiteButtonStyle: ButtonStyle {
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
                .font(.inter(13, kind == .primary ? .semibold : .medium))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .plain ? 10 : 12)
                .frame(height: 30)
                .background(background, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .opacity(configuration.isPressed ? 0.85 : 1)
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovered)
        }

        private var foreground: Color {
            switch kind {
            case .primary: isEnabled ? Graphite.onAccent : Graphite.text3
            case .ghost: isEnabled ? Graphite.text : Graphite.text3
            case .plain: isHovered && isEnabled ? Graphite.text : Graphite.text2
            }
        }

        private var background: Color {
            let hovered = isHovered && isEnabled
            switch kind {
            case .primary: return isEnabled ? (hovered ? Graphite.accentHover : Graphite.accent) : Graphite.fill
            case .ghost: return hovered ? Graphite.fillHover : Graphite.fill
            case .plain: return hovered ? Graphite.fill : .clear
            }
        }
    }
}

extension ButtonStyle where Self == GraphiteButtonStyle {
    static func graphite(_ kind: GraphiteButtonStyle.Kind) -> GraphiteButtonStyle { .init(kind: kind) }
}

/// A 28pt square glyph button.
struct GraphiteIconButtonStyle: ButtonStyle {
    var rest: Color = Graphite.text2

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
                .foregroundStyle(hovered ? Graphite.text : rest)
                .frame(width: 28, height: 28)
                .background(hovered ? Graphite.fillHover : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { isHovered = $0 }
        }
    }
}

/// Underlines on hover, like a text link.
struct TextLink: View {
    let label: Text
    var color: Color = Graphite.text2
    var hoverColor: Color = Graphite.text
    let action: () -> Void
    @State private var isHovered = false

    init(_ title: String, color: Color = Graphite.text2, hoverColor: Color = Graphite.text, action: @escaping () -> Void) {
        self.init(label: Text(title), color: color, hoverColor: hoverColor, action: action)
    }

    init(label: Text, color: Color = Graphite.text2, hoverColor: Color = Graphite.text, action: @escaping () -> Void) {
        self.label = label
        self.color = color
        self.hoverColor = hoverColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            label
                .underline(isHovered, color: Graphite.ink(0.35))
                .foregroundStyle(isHovered ? hoverColor : color)
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
                .foregroundStyle(isHovered ? Graphite.text : Graphite.text3)
                .frame(width: 28, height: 28)
                .background(isHovered ? Graphite.fillHover : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
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

/// A filled pop-up button: the current value and a chevron.
struct GraphiteMenu<Content: View>: View {
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
                    .font(.inter(13))
                    .foregroundStyle(Graphite.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Graphite.text3)
            }
            .padding(.leading, 11)
            .padding(.trailing, 9)
            .frame(width: width, height: 30)
            .background(isHovered ? Graphite.fillHover : Graphite.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
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

struct GraphiteSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? Graphite.accent : Graphite.switchOff)
                .frame(width: 34, height: 20)
                .overlay {
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
                        .offset(x: configuration.isOn ? 7 : -7)
                }
                .contentShape(Capsule())
                .animation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

extension ToggleStyle where Self == GraphiteSwitchStyle {
    static var graphiteSwitch: GraphiteSwitchStyle { .init() }
}

struct RadioMark: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(isOn ? Graphite.accent : Graphite.ink(0.32), lineWidth: 1.5)
            Circle()
                .fill(Graphite.accent)
                .frame(width: 8, height: 8)
                .scaleEffect(isOn ? 1 : 0.01)
        }
        .frame(width: 16, height: 16)
        .animation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.15), value: isOn)
        .accessibilityHidden(true)
    }
}

// MARK: - Fields

struct GraphiteFieldStyle: ViewModifier {
    let isFocused: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.inter(13.5))
            .foregroundStyle(Graphite.text)
            .focusEffectDisabled()
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(
                isFocused ? Graphite.fieldFocus : isHovered ? Graphite.fieldHover : Graphite.fill,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Graphite.ring, lineWidth: isFocused ? 1 : 0)
            }
            .onHover { isHovered = $0 }
    }
}

extension View {
    func graphiteField(focused: Bool) -> some View {
        modifier(GraphiteFieldStyle(isFocused: focused))
    }
}

/// A single-line field with its own placeholder: macOS ignores a `prompt`'s color.
struct GraphiteTextField<Field: Hashable>: View {
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
                    .font(.inter(13.5))
                    .foregroundStyle(Graphite.text3)
                    .lineLimit(1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .graphiteField(focused: focus.wrappedValue == field)
    }
}

/// A multi-line field with a placeholder, styled like `graphiteField`.
struct GraphiteTextEditor<Field: Hashable>: View {
    @Binding var text: String
    let placeholder: String
    let focus: FocusState<Field?>.Binding
    let field: Field
    @State private var isHovered = false

    var body: some View {
        let isFocused = focus.wrappedValue == field
        TextEditor(text: $text)
            .font(.inter(13.5))
            .lineSpacing(4)
            .foregroundStyle(Graphite.text)
            .scrollContentBackground(.hidden)
            .focused(focus, equals: field)
            .focusEffectDisabled()
            .padding(.horizontal, 6)
            .padding(.vertical, 9)
            .frame(minHeight: 96)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.inter(13.5))
                        .foregroundStyle(Graphite.text3)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
            }
            .background(
                isFocused ? Graphite.fieldFocus : isHovered ? Graphite.fieldHover : Graphite.fill,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Graphite.ring, lineWidth: isFocused ? 1 : 0)
            }
            .onHover { isHovered = $0 }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(label).font(.inter(12.5, .medium)).foregroundStyle(Graphite.text2)
                if isOptional {
                    Text("optional").font(.inter(12.5)).foregroundStyle(Graphite.text3)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.inter(13.5, .semibold))
                .foregroundStyle(Graphite.text)
                .accessibilityAddTraits(.isHeader)
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
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.inter(14.5)).foregroundStyle(Graphite.text)
                if let description {
                    Text(description)
                        .font(.inter(14))
                        .lineSpacing(4)
                        .foregroundStyle(isWarning ? Graphite.text : Graphite.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) { control() }
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle().fill(Graphite.hairline).frame(height: 1)
            }
        }
    }
}

// MARK: - Small pieces

struct Kbd: View {
    let key: String
    var isCompact = false

    init(_ key: String, isCompact: Bool = false) {
        self.key = key
        self.isCompact = isCompact
    }

    var body: some View {
        Text(key)
            .font(.graphiteMono(isCompact ? 10.5 : 11.5, .medium))
            .foregroundStyle(Graphite.text)
            .padding(.horizontal, isCompact ? 4 : 5)
            .frame(minWidth: isCompact ? 18 : 20, minHeight: isCompact ? 16 : 19)
            .background(Graphite.ink(0.09), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// "● In use" in the accent color.
struct DotLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Graphite.accent).frame(width: 6, height: 6)
            Text(text)
        }
        .foregroundStyle(Graphite.accent)
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
                .font(.inter(14))
                .foregroundStyle(Graphite.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(cancelTitle, action: onCancel)
                .buttonStyle(.graphite(.plain))
                .keyboardShortcut(.cancelAction)
            Button(confirmTitle, action: onConfirm)
                .buttonStyle(.graphite(.primary))
        }
    }
}

struct EmptyState<Accessory: View>: View {
    let title: String
    let accessory: () -> Accessory

    init(_ title: String, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.accessory = accessory
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.inter(15, .medium)).foregroundStyle(Graphite.text)
            accessory()
        }
        .font(.inter(14))
        .foregroundStyle(Graphite.text2)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .padding(.bottom, 24)
    }
}

/// A small text button that only shows a fill on hover, like a row's "Download".
struct GraphiteChipButtonStyle: ButtonStyle {
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
                .font(.inter(12.5))
                .foregroundStyle(hovered ? Graphite.text : Graphite.text2)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(hovered ? Graphite.fillHover : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { isHovered = $0 }
        }
    }
}

private struct HoverFill: ViewModifier {
    let cornerRadius: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? Graphite.hover : .clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

extension View {
    /// A soft fill while the pointer is over the view.
    func hoverFill(cornerRadius: CGFloat = 9) -> some View {
        modifier(HoverFill(cornerRadius: cornerRadius))
    }
}
