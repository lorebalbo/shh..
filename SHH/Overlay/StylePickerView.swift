import SwiftUI
import SwiftData

/// A compact, semi-transparent style picker displayed as a speech-bubble popup
/// attached to the recording overlay widget. Shows all available styles and
/// allows one-tap switching of the active style for the current recording.
struct StylePickerView: View {
    @ObservedObject var viewModel: StylePickerViewModel
    @State private var hoveredStyleId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Style list
            VStack(spacing: 2) {
                // "No style" option
                styleRow(
                    name: "No Style",
                    isActive: viewModel.activeStyleId == nil,
                    id: nil
                )

                if !viewModel.styles.isEmpty {
                    Divider()
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
            .padding(.vertical, 6)

            // Tail / arrow pointing toward the widget
            triangle
        }
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.appBackground.opacity(0.55))
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.appForeground.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
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
            .padding(.vertical, 6)
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

    // MARK: - Tail Arrow

    private var triangle: some View {
        Triangle()
            .fill(.ultraThinMaterial)
            .overlay(
                Triangle()
                    .fill(Color.appBackground.opacity(0.55))
            )
            .frame(width: 14, height: 7)
            .offset(y: -1)
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
