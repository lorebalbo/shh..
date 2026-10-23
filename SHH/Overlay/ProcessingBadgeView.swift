import SwiftUI

/// The "2 processing" label shown against the overlay widget while recordings
/// queue up. Hosted in its own click-through panel by OverlayWidgetController.
struct ProcessingBadgeView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        Text(viewModel.queueLabel ?? "")
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(.primary.opacity(0.8))
            .padding(.horizontal, 7)
            .frame(height: 14)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(Color.orange.opacity(0.6), lineWidth: 1))
            .frame(width: OverlayWidgetController.badgeSize.width, height: OverlayWidgetController.badgeSize.height)
    }
}
