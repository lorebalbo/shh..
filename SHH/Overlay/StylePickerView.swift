import SwiftUI
import SwiftData

enum StylePickerMetrics {
    static let width: CGFloat = 160
    static let rowHeight: CGFloat = 26
    static let padding: CGFloat = 4
    /// The hairline under "No Style", with its margins.
    static let separatorHeight: CGFloat = 9
    static let cornerRadius: CGFloat = 16
    static let maxHeight: CGFloat = 220
    static let minimumHeight: CGFloat = rowHeight + padding * 2

    static func height(styleCount: Int) -> CGFloat {
        let contentHeight = CGFloat(styleCount + 1) * rowHeight
            + (styleCount > 0 ? separatorHeight : 0)
            + padding * 2

        return min(max(contentHeight, minimumHeight), maxHeight)
    }
}

/// The style picker shown against the recording widget: a compact take on the dashboard's
/// menu in the widget's see-through ink, with a row per style and a check beside the active
/// one. One tap switches the active style for the current recording.
struct StylePickerView: View {
    @ObservedObject var viewModel: StylePickerViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: viewModel.styles.count > 7) {
            VStack(spacing: 0) {
                StyleRow(name: "No Style", isActive: viewModel.activeStyleId == nil) {
                    viewModel.selectStyle(id: nil)
                }

                if !viewModel.styles.isEmpty {
                    Rectangle()
                        .fill(Ink.inkHair)
                        .frame(height: 1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, (StylePickerMetrics.separatorHeight - 1) / 2)
                }

                ForEach(viewModel.styles) { style in
                    StyleRow(name: style.name, isActive: viewModel.activeStyleId == style.id) {
                        viewModel.selectStyle(id: style.id)
                    }
                }
            }
            .padding(StylePickerMetrics.padding)
        }
        .frame(width: StylePickerMetrics.width)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: StylePickerMetrics.cornerRadius, style: .continuous).inkGlass())
        .clipShape(RoundedRectangle(cornerRadius: StylePickerMetrics.cornerRadius, style: .continuous))
    }
}

/// A menu row: a capsule that lights up on hover, the check showing on the active style.
private struct StyleRow: View {
    let name: String
    let isActive: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .frame(width: 11)
                    .opacity(isActive ? 1 : 0)

                Text(name)
                    .font(.sans(12, isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .foregroundStyle(Ink.onInk)
            .padding(.leading, 9)
            .padding(.trailing, 10)
            .frame(height: StylePickerMetrics.rowHeight)
            .background(isHovered ? Ink.inkHover : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
