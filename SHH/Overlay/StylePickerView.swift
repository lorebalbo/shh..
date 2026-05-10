import SwiftUI
import SwiftData

enum StylePickerMetrics {
    static let width: CGFloat = 180
    static let rowHeight: CGFloat = 28
    static let rowSpacing: CGFloat = 2
    static let verticalPadding: CGFloat = 12
    static let dividerHeight: CGFloat = 1
    static let tailHeight: CGFloat = 7
    static let maxListHeight: CGFloat = 252
    static let minimumListHeight: CGFloat = rowHeight + verticalPadding
    static let minimumPanelHeight: CGFloat = minimumListHeight + tailHeight

    static func listHeight(styleCount: Int) -> CGFloat {
        let rowCount = styleCount + 1
        let spacingCount = styleCount > 0 ? rowCount : 0
        let contentHeight = CGFloat(rowCount) * rowHeight
            + CGFloat(spacingCount) * rowSpacing
            + (styleCount > 0 ? dividerHeight : 0)
            + verticalPadding

        return min(max(contentHeight, minimumListHeight), maxListHeight)
    }

    static func panelHeight(styleCount: Int) -> CGFloat {
        listHeight(styleCount: styleCount) + tailHeight
    }
}

/// A compact, semi-transparent style picker displayed as a speech-bubble popup
/// attached to the recording overlay widget. Shows all available styles and
/// allows one-tap switching of the active style for the current recording.
struct StylePickerView: View {
    @ObservedObject var viewModel: StylePickerViewModel
    @State private var hoveredStyleId: UUID?

    private var listHeight: CGFloat {
        StylePickerMetrics.listHeight(styleCount: viewModel.styles.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.placement == .belowWidget {
                triangle(pointsUp: true)
                    .offset(y: 1)
            }

            ScrollView(.vertical, showsIndicators: viewModel.styles.count > 7) {
                styleList
            }
            .frame(width: StylePickerMetrics.width, height: listHeight)
            .background(bubbleBackground)
            .overlay(bubbleBorder)
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)

            if viewModel.placement == .aboveWidget {
                triangle(pointsUp: false)
                    .offset(y: -1)
            }
        }
        .frame(width: StylePickerMetrics.width)
    }

    private var styleList: some View {
        VStack(spacing: StylePickerMetrics.rowSpacing) {
            styleRow(
                name: "No Style",
                isActive: viewModel.activeStyleId == nil,
                id: nil
            )

            if !viewModel.styles.isEmpty {
                Divider()
                    .frame(height: StylePickerMetrics.dividerHeight)
                    .background(Color.appForeground.opacity(0.1))
                    .padding(.horizontal, 8)
            }

            ForEach(viewModel.styles) { style in
                styleRow(
                    name: style.name,
                    isActive: viewModel.activeStyleId == style.id,
                    id: style.id
                )
            }
        }
        .padding(.vertical, StylePickerMetrics.verticalPadding / 2)
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.ultraThinMaterial)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.appBackground.opacity(0.55))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var bubbleBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.appForeground.opacity(0.12), lineWidth: 1)
    }

    private func triangle(pointsUp: Bool) -> some View {
        Triangle()
            .fill(.ultraThinMaterial)
            .overlay(
                Triangle()
                    .fill(Color.appBackground.opacity(0.55))
            )
            .frame(width: 14, height: StylePickerMetrics.tailHeight)
            .rotationEffect(.degrees(pointsUp ? 180 : 0))
    }

    // MARK: - Row

    private func styleRow(name: String, isActive: Bool, id: UUID?) -> some View {
        Button {
            viewModel.selectStyle(id: id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isActive ? Color.appError : Color.appForeground.opacity(0.35))

                Text(name)
                    .font(Font.appCaption)
                    .foregroundStyle(Color.appForeground)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: StylePickerMetrics.rowHeight)
            .background(
                (hoveredStyleId == id || (id == nil && hoveredStyleId == UUID(uuidString: "00000000-0000-0000-0000-000000000000")))
                    ? Color.appForeground.opacity(0.08)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            hoveredStyleId = isHovered ? (id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")) : nil
        }
        .padding(.horizontal, 4)
    }
}

/// A small downward-pointing triangle used as the speech bubble tail.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
