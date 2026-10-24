import CoreText
import SwiftUI

// MARK: - The mark

/// The face-and-hand mark (Assets.xcassets/AppMark, also the app icon's), traced into outlines:
/// the face, the hand, and three drops fanning out from the fingertip, in the PNG's 1001×1142 pixel space.
enum MarkOutline {
    static let size = CGSize(width: 1001, height: 1142)
    /// The frame around the three drops alone, for the small drops glyph.
    static let dropsFrame = CGRect(x: 664, y: 284, width: 170, height: 245)
    /// Where the drops fan out from, just beside the fingertip.
    static let sprayOrigin = CGPoint(x: 660, y: 480)

    static let face = points([
        291, 7, 322, 7, 353, 11, 377, 19, 394, 31, 403, 42, 408, 57, 408, 76, 404, 108, 407, 124, 414, 135, 427, 149,
        445, 162, 530, 208, 563, 231, 576, 246, 585, 261, 588, 276, 587, 292, 584, 304, 575, 317, 566, 326, 552, 335,
        539, 340, 521, 344, 455, 348, 440, 354, 432, 363, 430, 375, 436, 387, 448, 393, 477, 399, 490, 405, 500, 416,
        503, 424, 504, 433, 499, 444, 487, 455, 473, 460, 433, 465, 424, 472, 424, 479, 430, 485, 438, 489, 477, 498,
        491, 503, 497, 508, 504, 516, 506, 530, 502, 542, 496, 549, 489, 553, 466, 560, 454, 571, 449, 584, 446, 609,
        440, 629, 430, 646, 417, 660, 394, 677, 369, 688, 341, 697, 300, 706, 250, 712, 211, 714, 169, 712, 136, 707,
        101, 696, 69, 680, 43, 657, 26, 634, 11, 601, 6, 569, 10, 538, 19, 511, 33, 487, 50, 467, 69, 452, 89, 440,
        132, 424, 236, 400, 259, 392, 275, 384, 289, 374, 300, 361, 306, 347, 307, 335, 304, 322, 296, 309, 285, 298,
        271, 290, 238, 278, 186, 265, 157, 256, 133, 245, 111, 230, 96, 214, 82, 189, 77, 164, 79, 141, 88, 115,
        102, 95, 122, 74, 154, 50, 188, 32, 220, 20, 258, 11
    ])

    static let hand = points([
        576, 380, 587, 380, 600, 384, 611, 391, 620, 401, 634, 428, 644, 469, 648, 513, 647, 593, 640, 665, 628, 742,
        630, 759, 637, 769, 646, 773, 657, 771, 663, 765, 667, 754, 666, 735, 656, 685, 656, 666, 660, 647, 667, 636,
        676, 627, 686, 621, 698, 618, 716, 619, 732, 626, 742, 636, 749, 651, 752, 669, 751, 686, 744, 733, 742, 757,
        744, 768, 751, 774, 759, 772, 764, 763, 761, 714, 766, 689, 773, 677, 780, 670, 798, 661, 815, 660, 830, 664,
        842, 672, 852, 685, 857, 702, 858, 715, 848, 787, 851, 796, 856, 801, 864, 800, 869, 793, 872, 731, 878, 714,
        890, 699, 901, 693, 910, 690, 922, 689, 933, 690, 944, 694, 953, 700, 965, 716, 969, 729, 971, 745, 967, 836,
        969, 874, 974, 904, 991, 966, 994, 984, 992, 1011, 982, 1044, 964, 1072, 939, 1095, 909, 1112, 883, 1121,
        853, 1128, 825, 1132, 787, 1135, 722, 1132, 692, 1127, 664, 1120, 637, 1110, 617, 1100, 599, 1089, 580, 1074,
        556, 1050, 542, 1032, 528, 1010, 516, 986, 503, 952, 489, 902, 466, 799, 446, 722, 443, 703, 443, 687,
        446, 671, 453, 655, 463, 644, 475, 637, 491, 635, 504, 638, 515, 645, 525, 657, 533, 675, 538, 699, 536, 724,
        529, 776, 529, 806, 536, 834, 544, 849, 549, 854, 552, 780, 564, 680, 565, 604, 558, 545, 539, 465, 536, 435,
        540, 414, 548, 398, 561, 386
    ])

    /// Top to bottom.
    static let drops = [
        points([
            713, 289, 726, 290, 737, 298, 743, 312, 742, 325, 735, 339, 713, 367, 680, 408, 676, 412, 672, 412,
            669, 409, 669, 404, 677, 342, 681, 324, 687, 309, 694, 299, 702, 292
        ]),
        points([
            793, 365, 801, 364, 810, 366, 819, 371, 825, 379, 828, 388, 827, 398, 824, 406, 817, 414, 806, 421,
            787, 427, 708, 445, 702, 445, 698, 444, 697, 440, 699, 436, 746, 395, 773, 374
        ]),
        points([
            734, 470, 768, 471, 782, 473, 792, 477, 800, 483, 805, 491, 806, 501, 804, 511, 796, 520, 788, 523,
            774, 523, 762, 518, 728, 495, 708, 479, 708, 474, 711, 471
        ]),
    ]

    /// The way a drop flies: from the spray origin through its middle, as a unit vector.
    static func direction(of drop: [CGPoint]) -> CGVector {
        let center = CGPoint(
            x: drop.map(\.x).reduce(0, +) / CGFloat(drop.count),
            y: drop.map(\.y).reduce(0, +) / CGFloat(drop.count)
        )
        let dx = center.x - sprayOrigin.x
        let dy = center.y - sprayOrigin.y
        let length = max(hypot(dx, dy), 1)
        return CGVector(dx: dx / length, dy: dy / length)
    }

    private static func points(_ xy: [CGFloat]) -> [CGPoint] {
        stride(from: 0, to: xy.count - 1, by: 2).map { CGPoint(x: xy[$0], y: xy[$0 + 1]) }
    }

    /// Polygons from the outline, fitted into `rect` the way `frame` would be with aspect-fit.
    static func path(_ outlines: [[CGPoint]], frame: CGRect, in rect: CGRect) -> Path {
        let scale = min(rect.width / frame.width, rect.height / frame.height)
        let origin = CGPoint(
            x: rect.midX - frame.width * scale / 2 - frame.minX * scale,
            y: rect.midY - frame.height * scale / 2 - frame.minY * scale
        )
        var path = Path()
        for outline in outlines {
            path.addLines(outline.map { CGPoint(x: origin.x + $0.x * scale, y: origin.y + $0.y * scale) })
            path.closeSubpath()
        }
        return path
    }
}

/// Pieces of the mark, drawn in the whole mark's frame so the pieces line up when stacked.
struct MarkPiece: Shape {
    let outlines: [[CGPoint]]
    var frame = CGRect(origin: .zero, size: MarkOutline.size)

    func path(in rect: CGRect) -> Path {
        MarkOutline.path(outlines, frame: frame, in: rect)
    }
}

/// The face and hand with their drops. Hovering sprays the drops out from the fingertip and back.
struct InkMarkView: View {
    var spraysOnHover = false
    @State private var sprays = 0

    var body: some View {
        GeometryReader { geometry in
            let unit = geometry.size.height / MarkOutline.size.height
            ZStack {
                MarkPiece(outlines: [MarkOutline.face, MarkOutline.hand])
                ForEach(0..<3, id: \.self) { index in
                    let drop = MarkOutline.drops[index]
                    let away = MarkOutline.direction(of: drop)
                    MarkPiece(outlines: [drop])
                        .keyframeAnimator(initialValue: CGFloat(0), trigger: sprays) { piece, out in
                            piece.offset(x: away.dx * out * 60 * unit, y: away.dy * out * 60 * unit)
                        } keyframes: { _ in
                            LinearKeyframe(0, duration: 0.05 * Double(index))
                            CubicKeyframe(1, duration: 0.2)
                            SpringKeyframe(0, duration: 0.4, spring: .bouncy)
                        }
                }
            }
        }
        .aspectRatio(MarkOutline.size.width / MarkOutline.size.height, contentMode: .fit)
        .onHover { inside in
            if inside && spraysOnHover { sprays += 1 }
        }
        .accessibilityHidden(true)
    }
}

/// The three drops on their own: a splash when they appear (`.splash`), or a pulsing wait (`.loading`).
struct InkDrops: View {
    enum Motion { case splash, loading }
    let motion: Motion
    var height: CGFloat = 13

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let outline = MarkOutline.drops[index]
                let drop = MarkPiece(outlines: [outline], frame: MarkOutline.dropsFrame)
                switch motion {
                case .splash: SplashingDrop(drop: drop, away: MarkOutline.direction(of: outline), index: index, height: height)
                case .loading: PulsingDrop(drop: drop, index: index)
                }
            }
        }
        .frame(width: height * MarkOutline.dropsFrame.width / MarkOutline.dropsFrame.height, height: height)
        .accessibilityHidden(true)
    }

    /// Flies out from the fingertip into place.
    private struct SplashingDrop: View {
        let drop: MarkPiece
        let away: CGVector
        let index: Int
        let height: CGFloat
        @State private var isOut = false

        var body: some View {
            let back = 70 * height / MarkOutline.dropsFrame.height
            drop
                .offset(x: isOut ? 0 : -away.dx * back, y: isOut ? 0 : -away.dy * back)
                .scaleEffect(isOut ? 1 : 0.2)
                .opacity(isOut ? 1 : 0)
                .onAppear {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.55).delay(0.05 * Double(index))) {
                        isOut = true
                    }
                }
        }
    }

    /// The loading pulse of drop `index` at `date`, from 0 to 1: once a second, staggered by
    /// 0.15s per drop, up over the first 40% of the second and back down over the rest.
    static func drip(at date: Date, index: Int) -> Double {
        let t = (date.timeIntervalSinceReferenceDate - 0.15 * Double(index))
            .truncatingRemainder(dividingBy: 1)
        let up = t < 0.4 ? t / 0.4 : 1 - (t - 0.4) / 0.6
        return 0.5 - cos(up * .pi) / 2
    }

    private struct PulsingDrop: View {
        let drop: MarkPiece
        let index: Int

        var body: some View {
            TimelineView(.animation) { context in
                drop.opacity(0.2 + 0.8 * InkDrops.drip(at: context.date, index: index))
            }
        }
    }
}

// MARK: - Display type

/// Rock 3D, the display face, for the brand, page titles and section titles. It's drawn in hairline
/// outlines, so the glyphs are stroked to carry the weight of the ink shapes (CSS `-webkit-text-stroke`),
/// and its very wide space is tightened. Single line; draws in the foreground style.
struct DisplayText: View {
    private let text: String
    private let glyphs: Path
    private let size: CGSize
    private let stroke: CGFloat

    /// - Parameters:
    ///   - lineHeight: the line box, as a multiple of `fontSize`; the glyphs sit in it like CSS half-leading.
    init(_ text: String, size fontSize: CGFloat, stroke: CGFloat = 0.6, lineHeight: CGFloat = 1.2, tracking: CGFloat = 0.01) {
        self.text = text
        self.stroke = stroke
        let font = CTFontCreateWithName("Rock3D-Regular" as CFString, fontSize, nil)
        let string = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .kern: tracking * fontSize,
        ])
        let nsText = text as NSString
        for index in 0..<nsText.length where nsText.character(at: index) == 0x20 {
            string.addAttribute(.kern, value: (tracking - 0.32) * fontSize, range: NSRange(location: index, length: 1))
        }
        let line = CTLineCreateWithAttributedString(string)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        let height = fontSize * lineHeight
        let baseline = (height - ascent - descent) / 2 + ascent

        let path = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName] as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphIDs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphIDs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for (glyph, position) in zip(glyphIDs, positions) {
                guard let outline = CTFontCreatePathForGlyph(runFont, glyph, nil) else { continue }
                // Core Text draws y-up from the baseline; SwiftUI is y-down from the top.
                path.addPath(outline, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: position.x, ty: baseline - position.y))
            }
        }
        glyphs = Path(path)
        size = CGSize(width: ceil(width), height: height)
    }

    var body: some View {
        glyphs
            .fill()
            .overlay { glyphs.stroke(style: StrokeStyle(lineWidth: stroke, lineJoin: .round)) }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .accessibilityElement()
            .accessibilityLabel(text)
    }
}

// MARK: - The sidebar's tab

/// The current page in the sidebar: a paper tab reaching out of the page into the ink blob, round
/// on the left, with concave corners where it meets the blob's edge on the right.
/// `rect` is the tab's body; the concave corners are drawn just above and below it.
struct LiquidTab: Shape {
    var cornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        let end = rect.height / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY - r))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.minY), radius: r)
        path.addLine(to: CGPoint(x: rect.minX + end, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: end)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: end)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY + r), radius: r)
        path.closeSubpath()
        return path
    }
}
