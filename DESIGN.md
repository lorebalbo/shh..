# Design System Specification: The Fremen Codex

This design system is an editorial interpretation of a future forged by scarcity and wisdom. It draws from the mythos of a world where technology is inseparable from survival — where every instrument must be compact, functional, and carved from the earth itself. It is a system of **warm brutalism**: uncompromisingly structured, yet alive with the amber glow of a desert sun.

## 1. Overview & Creative North Star

**Creative North Star: The Stillsuit Terminal.**

The SHH interface is a piece of *Fremen technology* — a precision instrument built not in a laboratory, but under a desert sky. It is functional before it is beautiful, but through that function, it achieves a brutal elegance. Every surface evokes sun-bleached sandstone and baked mineral clay. Every text element reads like an inscription carved into a rock face: clear, permanent, authoritative.

The application's core tension is between **voice and silence**. SHH is an app that *listens*, that converts the ephemeral (speech) into the permanent (text). This creates the central design metaphor: the interface must feel like a vessel — quiet and contained until activated, then pulsing with a deep, internal energy. The overlay widget, in particular, should feel like a single, glowing spice-eye in the corner of the screen.

We achieve the "not-template" look through **radical restraint and tonal density**. The palette is almost monochromatic — a warm off-white field dominated by a single stone-gray — broken only by the precise, deliberate intrusion of Spice Fire on interactive and status elements. Layouts are built on a rigid 52pt column header rhythm, creating a scannable, schematic structure. Depth is never achieved through decorative shadow; it is achieved through the deliberate excavation of surface tiers.

---

## 2. Colors

The palette is austere and mineral. It takes its cues from a desert at the moment before sunset: a pale, almost bleached sky above, a field of dark exposed rock below, and a single burning ember of spice-light on the horizon.

### Core Palette

| Token | Hex | Name | Role |
|---|---|---|---|
| `Color.appBackground` | `#F6F7EB` | **Desert Sand** | Foundational surface for all primary view panels. Warm, off-white. |
| `Color.appForeground` | `#393E41` | **Stillsuit Stone** | The universal ink. All text, borders, icons, and tonal fills derive from this single base. |
| `Color.appError` | `#E94F37` | **Spice Fire** | The sole accent color. Used exclusively for active states, primary CTAs, and critical status. |

### The Opacity Architecture of Stillsuit Stone

The entire interface depth system is constructed from a single foreground color applied at precisely controlled opacity levels. Do not introduce additional colors for tonal variation. This monochromatic discipline is the system's defining characteristic.

| Opacity | Rendered tone | Application |
|---|---|---|
| `1.0` | Full Stone | Primary body text, labels, active icons |
| `0.8` | Worn Stone | Secondary/inactive icon fills |
| `0.7` | Aged Rock | Form section labels, sheet dismiss button |
| `0.6` | Brushed Metal | Secondary body text, caption labels |
| `0.5` | Dust | Counter/meta text |
| `0.45` | Fine Sand | Empty-state body copy, timestamps |
| `0.35` | Shadow | Inactive row action icon buttons |
| `0.25` | Pale Dune | Empty-state hero icons |
| `0.15` | Selected Stratum | Selected sidebar row background fill |
| `0.12` | Deep Haze | Card/input border strokes, internal dividers, disabled button fill |
| `0.10` | Ghost Veil | Section card border overlays; keyboard shortcut key bg |
| `0.08` | Surface Hover | Hovered row/card background lift |
| `0.07` | Cancel Fill | Secondary button background |
| `0.06` | Input Excavation | Text field and text editor background ("cutout" feel) |
| `0.05` | Card Stratum | Default card/section block background |
| `0.03` | Entry Whisper | Dictation entry card default background |

### Spice Fire Usage Rules (`#E94F37`)

Spice Fire is the *only* warm accent. Its presence must be intentional and earned.

- **Mandatory use:** Primary CTA button fill (Save, Create, Add), `"Active"` status badge background, toggle `on` state, sidebar selected item text/icon, waveform bars, style picker active checkmark.
- **Prohibited use:** Body text, section backgrounds, borders, shadows, placeholders, decorative elements.

### The "No-Warm-Gradient" Rule

Do not introduce smooth color gradients between palette values. The app has no gradients. Tonal transitions are achieved through discrete, quantized opacity steps, not continuous blends. If a transitional texture is required, a sharp, stepped opacity change is acceptable.

---

## 3. Typography

The sole typeface is **League Spartan**. Its wide, geometric construction carries the weight of Imperial desert inscriptions — broad strokes, open counters, and a quiet authority that reads as both technical and ancient. It must not be substituted.

### Type Scale

All text elements must use the following tokens. Monospaced exceptions are noted explicitly.

| Token | Font | Size | Semantic equivalent |
|---|---|---|---|
| `Font.appLargeTitle` | League Spartan | 30pt | `.largeTitle` |
| `Font.appTitle` | League Spartan | 26pt | `.title` |
| `Font.appTitle2` | League Spartan | 20pt | `.title2` |
| `Font.appTitle3` | League Spartan | 18pt | `.title3` |
| `Font.appHeadline` | League Spartan | 15pt | `.headline` (semibold) |
| `Font.appSubheadline` | League Spartan | 13pt | `.subheadline` |
| `Font.appBody` | League Spartan | 15pt | `.body` |
| `Font.appCallout` | League Spartan | 14pt | `.callout` |
| `Font.appFootnote` | League Spartan | 12pt | `.footnote` |
| `Font.appCaption` | League Spartan | 11pt | `.caption` |
| `Font.appCaption2` | League Spartan | 10pt | `.caption2` |

### Typographic Application Rules

| Element | Token | Weight |
|---|---|---|
| Panel/view header title | `appTitle3` (18pt) | `.bold` |
| Section group labels | `appHeadline` (15pt) | semibold (built-in) |
| Form field labels | `appSubheadline` (13pt) | `.semibold` |
| Body copy, row labels, button text | `appBody` (15pt) | varies by context |
| Search fields, callout text | `appCallout` (14pt) | regular |
| Sidebar navigation row labels | League Spartan 14pt | regular |
| `"Active"` badge | `appCaption2` (10pt) | `.semibold` |
| Keyboard shortcut key badge | League Spartan 15pt, `.monospaced()` style | regular |
| Onboarding title | `appTitle` (26pt) | `.bold` |
| Diagnostic/pipeline log timestamps | System `.caption2`, `.monospaced` design | — |
| Diagnostic/pipeline log messages | System `.caption`, `.monospaced` design | — |

### Monospaced Exception

Use `system(.caption, design: .monospaced)` and `system(.caption2, design: .monospaced)` only for pipeline event logs and internal diagnostic data. These are technical readouts, not UI text. All user-facing content must use League Spartan.

### Typography as Architecture

The 52pt header bar — a fixed-height block topped with an `appTitle3 + .bold` label — functions as a structural beam. It is the single most authoritative typographic element per panel, and it anchors the vertical rhythm of the entire view. Headers must never be decorative; they are load-bearing.

---

## 4. Elevation & Depth

Elevation in this system is geological. Depth is expressed through the **stratification of the Desert Sand field** using the Stillsuit Stone opacity tiers. Think of it as rock strata: you excavate deeper surfaces by filling them with progressively higher-opacity Stone overlaid on Sand.

There are zero decorative drop shadows in this system. The one exception is the StylePicker popup, which uses an ambient shadow at minimal opacity to signal that it is a detached floating layer.

### Depth Tiers (from surface to deepest)

| Level | Background fill | Context |
|---|---|---|
| **Floating Glass** | `.ultraThinMaterial` + `appBackground.opacity(0.55)` | Overlay widget, StylePicker popup — "Mirage" layer |
| **Surface** | `Color.appBackground` (`#F6F7EB`) | All primary view panels, sheets |
| **Card** | `appForeground.opacity(0.05)` | Section info cards, list row cards |
| **Input Excavation** | `appForeground.opacity(0.06)` | Text fields, text editors — slightly deeper than card |
| **Hovered Card** | `appForeground.opacity(0.08)` | Card row on hover |
| **Entry Whisper** | `appForeground.opacity(0.03)` | Dictation entry card default — barely below surface |
| **Selected Stratum** | `appForeground.opacity(0.15)` | Active sidebar selection — deepest non-accent fill |

### The Mirage Glass Effect

Floating UI elements (the Overlay Widget and StylePicker popup) must use `.ultraThinMaterial` combined with `appBackground.opacity(0.55)` to achieve a layered, semi-transparent sand-glass quality. This is the system's signature "atmospheric" texture — it should feel like a heat mirage floating above the desktop, not a hard opaque surface.

### Shadow Policy

| Situation | Shadow allowed | Spec |
|---|---|---|
| StylePicker popup | Yes | `color: .black, opacity: 0.12, radius: 8, x: 0, y: 2` |
| Overlay NSPanel | Yes (system) | `hasShadow = true` (system handles) |
| AppToggle thumb | Yes (micro) | `shadow(radius: 1)` only |
| All cards and panels | **No** | Depth via tonal stacking only |
| All sheet modals | **No** | Background is flat `appBackground` |

---

## 5. Components

### Layout Grid & Rhythm

All panels share a structural template built on three invariant regions:

```
┌─────────────────────────────────────────────┐
│  HEADER BAR — fixed 52pt height             │
│  HStack: title (appTitle3 .bold) + actions  │
├─────────────────────────────────────────────┤
│  Divider (system)                           │
├─────────────────────────────────────────────┤
│  SCROLLABLE CONTENT                         │
│  VStack, 24pt horizontal padding            │
│  24pt top/bottom scroll insets              │
└─────────────────────────────────────────────┘
```

This three-region pattern is mandatory for all primary navigation views and all sheet modals. Sheet modals add a fourth region: an action footer (Divider → HStack of Cancel/Save at 16pt vertical, 24pt horizontal padding).

### Dashboard Shell

- `HStack(spacing: 0)`: sidebar left, 1pt divider, content pane right.
- Sidebar: 180pt expanded, 64pt collapsed, animated with `.spring(duration: 0.3)`.
- Minimum window: 700×500pt. Default: 800×550pt.
- The 1pt structural divider uses `Rectangle().frame(width: 1).foregroundStyle(appForeground.opacity(0.12))`. It is the *only* internal vertical rule permitted.

### Section Cards / Info Blocks

Used in `HelpView` and `SettingsView`.

```swift
VStack(alignment: .leading, spacing: 12)
    .padding(16)
    .background(Color.appForeground.opacity(0.05))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.appForeground.opacity(0.10), lineWidth: 1)
    }
```

### List Row Cards (Style rows, Provider rows)

```swift
HStack(spacing: 12)
    .padding(20)
    .background(isHovered ? Color.appForeground.opacity(0.08) : Color.appForeground.opacity(0.05))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.appForeground.opacity(0.10), lineWidth: 1)
    }
    .listRowSeparator(.hidden)
    .padding(.vertical, 2)
```

`List` must always use `.listStyle(.inset)`, `.scrollContentBackground(.hidden)`, and an explicit `Color.appBackground` background.

### Form Input Fields

All text fields, secure fields, and text editors use the "excavated" look.

```swift
TextField(...)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Color.appForeground.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.appForeground.opacity(0.12), lineWidth: 1)
    }
```

`TextEditor` minimum height for long-form fields (e.g., system prompts): 140pt.

### Buttons

**Primary CTA (Save / Create / Add):**
```swift
Text(label)
    .font(Font.appBody).fontWeight(.semibold)
    .foregroundStyle(isValid ? .white : Color.appForeground.opacity(0.4))
    .padding(.horizontal, 16).padding(.vertical, 8)
    .background(isValid ? Color.appError : Color.appForeground.opacity(0.12))
    .clipShape(RoundedRectangle(cornerRadius: 6))
```

**Secondary / Cancel:**
```swift
Text("Cancel")
    .font(Font.appBody)
    .foregroundStyle(Color.appForeground.opacity(0.7))
    .padding(.horizontal, 16).padding(.vertical, 8)
    .background(Color.appForeground.opacity(0.07))
    .clipShape(RoundedRectangle(cornerRadius: 6))
```

Buttons never use shadows. The only color state change that communicates interaction is the fill: `appError` solid when active/valid, `appForeground.opacity(0.12)` when disabled.

### Active / Status Badge

```swift
Text("Active")
    .font(Font.appCaption2).fontWeight(.semibold)
    .foregroundStyle(.white)
    .padding(.horizontal, 8).padding(.vertical, 2)
    .background(Color.appError)
    .clipShape(Capsule())
```

`Capsule()` is the *only* context where non-zero corner radius curves are used on a non-circular badge. This exception marks status pills as categorically different from structural UI cards.

### Custom Toggle (`AppToggleStyle`)

- Container: `Capsule()`, 38×22pt. Background: `appError` (on) / `appForeground.opacity(0.25)` (off).
- Thumb: `Circle()`, 18×18pt, `.white`, `shadow(radius: 1)`.
- Offset: `±8pt` on X. Transition: `.easeInOut(duration: 0.15)`.
- Apply `.tint(Color.appError)` to system `Toggle` and `Picker` controls in `SettingsView`.

### Sidebar Navigation Rows

- Icon: SF Symbol at 13pt, constrained to a 20×20pt frame.
- Label: League Spartan 14pt.
- Row container: `RoundedRectangle(cornerRadius: 6)`, padding `.vertical(6) .horizontal(10)`.
- State backgrounds: selected `appForeground.opacity(0.15)`, hovered `appForeground.opacity(0.08)`, default transparent.
- State foreground: selected `appError`, hovered `appForeground` full, default `appForeground.opacity(0.8)`.

### Empty States

```swift
VStack(spacing: 12) {
    Image(systemName: "waveform") // or contextual symbol
        .font(.system(size: 36))
        .foregroundStyle(Color.appForeground.opacity(0.25))
    Text(title)
        .font(Font.appTitle3).fontWeight(.semibold)
    Text(description)
        .font(Font.appBody)
        .foregroundStyle(Color.appForeground.opacity(0.45))
        .multilineTextAlignment(.center)
}
.padding(24)
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

### Overlay Widget (The Spice Eye)

The overlay is the heart of the system. It must feel minimal, floating, and semi-alive.

- Frame: 88×22pt total, 80×16pt rendered content area.
- Background: `.ultraThinMaterial` ("Mirage Glass").
- Border: `1.5pt` stroke. Idle: `Color.primary.opacity(0.15)`. Recording: `Color.red.opacity(0.6)`.
- Corner radius: `9pt, style: .continuous`.
- Tap: scale `→ 0.85 → 1.0`, each step `.easeInOut(duration: 0.1)`, with `0.1s` delay between.
- Recording state transition: `.easeInOut(duration: 0.25)` opacity crossfade between idle icon and waveform.
- Panel: `.floating` level, `.borderless`, `.nonactivatingPanel`, `hasShadow: true`.
- Snap to nearest screen edge on drag release: `NSAnimationContext` duration `0.2`, `easeInEaseOut`.

### Waveform Bars

- 5 bars in `HStack(spacing: 2pt)`.
- Each bar: 3pt wide, `RoundedRectangle(cornerRadius: 1.5)`, filled with `Color.appError` (Spice Fire).
- Height: sine-wave modulation, range `[1.5pt, 10pt]`.
- Animation driver: `TimelineView` at 30fps, per-bar phase offset `0.65 * index`.

### StylePicker Popup (The Speech Bubble)

- Width: 180pt, height dynamic.
- Background: `.ultraThinMaterial` + `Color.appBackground.opacity(0.55)`.
- Border: `1pt`, `appForeground.opacity(0.12)`, `cornerRadius: 10, style: .continuous`.
- Drop shadow: `color: .black, opacity: 0.12, radius: 8, y: 2`.
- Tail: custom `Triangle` shape (14×7pt), same material/background fill.
- Show: `NSAnimationContext` fade-in `0.15s easeOut`. Hide: fade-out `0.12s easeIn`.

### Dictation Entry Cards

- Corner radius: `10pt`.
- Default background: `appForeground.opacity(0.03)`.
- Default border: `appForeground.opacity(0.12)`, `1pt`.
- Hovered border: `appForeground.opacity(0.25)`, `1pt`.
- Hovered background: `appForeground.opacity(0.07)`.
- Internal dividers: `Rectangle().fill(appForeground.opacity(0.12))`, `1pt`, padded `8pt`.
- Minimum height: `122pt`.
- Transition: `.easeInOut(duration: 0.15)` on hover state changes.

---

## 6. Spacing System

All spacing values are drawn from a small set of discrete steps. Do not introduce arbitrary values.

| Token | Value | Primary use |
|---|---|---|
| `space-xs` | 2pt | Internal HStack bar spacing; list row vertical inset |
| `space-sm` | 6pt | Form label-to-input gap; sidebar row vertical padding |
| `space-md` | 8pt | Button/badge horizontal padding; section element vertical gaps |
| `space-base` | 12pt | Card internal spacing; onboarding step content |
| `space-lg` | 16pt | Form footer; card inner padding; section-to-section gap |
| `space-xl` | 20pt | Card row internal padding; detail content vertical padding |
| `space-2xl` | 24pt | Universal horizontal edge padding; scroll insets; major section gaps |
| `space-3xl` | 52pt | Header bar height (invariant) |

---

## 7. Corner Radius Registry

Corner radius values are fixed and must not be improvised. Each value maps to a specific component class.

| Radius | Component |
|---|---|
| `0pt` | None — this system does not use sharp 0pt corners. Minimum is `6pt`. |
| `1.5pt` | WaveformView animated bars |
| `4pt` | Keyboard shortcut key badge |
| `6pt` | Buttons (CTA and cancel); sidebar nav row items; style picker row items |
| `8pt` | Section info cards; list row cards; form input fields; all sheets' inner blocks |
| `9pt` (`.continuous`) | Overlay widget |
| `10pt` (`.continuous`) | Dictation entry cards; StylePickerView container |
| `Capsule()` | Active/status pills; AppToggleStyle background |
| `Circle()` | AppToggleStyle thumb; onboarding step number circle |

---

## 8. Do's and Don'ts

### Do:

- **Use tonal stacking for depth.** Achieving a "raised" or "recessed" effect means shifting background opacity, never adding a shadow. An input at `0.06` opacity sits visually deeper than a card at `0.05` opacity, which sits deeper than the `appBackground` surface.
- **Treat `appError` (Spice Fire) as a precious resource.** Every use of `#E94F37` is a signal. If everything is Spice Fire, nothing is. Reserve it for: active states, primary CTAs, recording indicators, selected items.
- **Use the 52pt header bar as an anchor.** Every panel opens with this bar. It is the visual "ground floor" from which content descends. Do not deviate from this height.
- **Honor League Spartan exclusively.** Every text element — labels, buttons, headers, placeholders — must render in this typeface. It is non-negotiable. The only exception is pipeline/diagnostic log data, which uses system monospaced.
- **Apply the Mirage Glass stack correctly.** Floating or overlay surfaces must use `.ultraThinMaterial` AND `appBackground.opacity(0.55)` together, not either alone. The combination creates the characteristic warm-sand translucency.
- **Keep borders subtle and structural.** Internal card borders use `appForeground.opacity(0.10)` at `1pt`. Recording state overlay borders use `Color.red.opacity(0.6)` at `1.5pt`. These are the only two border-weight contexts.

### Don't:

- **Don't introduce new hues.** The palette has three entries. Do not add warm yellows, sandy oranges, or dusty taupes as "complementary" colors. The warmth of the palette comes from `#F6F7EB` and `#E94F37`, not from decoration.
- **Don't use decorative drop shadows.** No `shadow(color:radius:x:y:)` on cards, list rows, or sheet panels. Depth is geological — built through color, not light.
- **Don't round corners beyond the registry.** The temptation to use `12pt` or `16pt` radius on cards must be resisted. The `8pt` card radius and `10pt` entry card radius define the organic-yet-angular quality of this system. More rounding reads as generic iOS, not desert-cut stone.
- **Don't use `Divider()` for internal section separation inside panels.** Use background opacity shifts or `spacing` gaps. `Divider()` is only permitted in the structural seam between the header bar and scrollable content, and in sheet modal footer separators.
- **Don't animate layout changes.** Animations are reserved for state transitions (toggle, recording state, hover) and spatial transitions (overlay drag, sidebar collapse). Content reflow must be instantaneous.
- **Don't substitute system colors for custom tokens.** Avoid `.primary`, `.secondary`, `.accentColor` in new UI code. Use `Color.appForeground`, `Color.appBackground`, `Color.appError` directly. System semantic colors produce inconsistent results across macOS appearance modes.
- **Don't create gradient fills.** No `LinearGradient`, `RadialGradient`, or `AngularGradient` on any surface. The only motion-driven fill is the WaveformView bar height, which is solid `appError`.
- **Don't use `.listStyle(.plain)` or `.sidebar`.** All lists must use `.listStyle(.inset)` with `.scrollContentBackground(.hidden)` and an explicit `Color.appBackground` backing. Any other style will destroy the card row appearance.
- **Don't mix `appError` with Capsule shapes outside of status badges.** The Capsule shape is reserved for the Active badge and the AppToggleStyle. Using it for buttons or other interactive elements breaks the semantic distinction between "status communication" and "action invocation."
