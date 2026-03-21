import SwiftUI

extension Font {
    static var appLargeTitle: Font { .custom("League Spartan", size: 30, relativeTo: .largeTitle) }
    static var appTitle: Font { .custom("League Spartan", size: 26, relativeTo: .title) }
    static var appTitle2: Font { .custom("League Spartan", size: 20, relativeTo: .title2) }
    static var appTitle3: Font { .custom("League Spartan", size: 18, relativeTo: .title3) }
    static var appHeadline: Font { .custom("League Spartan", size: 15, relativeTo: .headline).weight(.semibold) }
    static var appSubheadline: Font { .custom("League Spartan", size: 13, relativeTo: .subheadline) }
    static var appBody: Font { .custom("League Spartan", size: 15, relativeTo: .body) }
    static var appCallout: Font { .custom("League Spartan", size: 14, relativeTo: .callout) }
    static var appFootnote: Font { .custom("League Spartan", size: 12, relativeTo: .footnote) }
    static var appCaption: Font { .custom("League Spartan", size: 11, relativeTo: .caption) }
    static var appCaption2: Font { .custom("League Spartan", size: 10, relativeTo: .caption2) }
}
