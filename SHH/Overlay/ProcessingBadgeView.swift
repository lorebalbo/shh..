import SwiftUI

/// The "2 processing" label shown below the overlay widget while recordings
/// queue up. Hosted in its own click-through panel by OverlayWidgetController.
struct ProcessingBadgeView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        Text(viewModel.queueLabel ?? "")
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            // No pill or outline: just a blur that fades out at its edges, so the
            // label stays readable over whatever is under it (often the Dock).
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(Capsule().padding(3).blur(radius: 3))
            }
            .frame(width: OverlayWidgetController.badgeSize.width, height: OverlayWidgetController.badgeSize.height)
    }
}
