import SwiftUI

/// NIIMBOT orange on warm white, from the Claude Design handoff (Niim Redesign.dc.html).
enum Theme {
    static let accent = Color(hex: 0xFF6A1F)
    static let accentInk = Color(hex: 0xC1480A)  // text on tints
    static let wash = Color(hex: 0xFFF3EB)
    static let washActive = Color(hex: 0xFFF1E7)
    static let washPressed = Color(hex: 0xFFE7D8)
    static let washBorder = Color(hex: 0xFFD9C2)
    static let buttonBorder = Color(hex: 0xFFD0B2)
    static let disabled = Color(hex: 0xF0D9C8)  // disabled Print, tape edge
    static let window = Color(hex: 0xFFFDFB)
    static let inspector = Color(hex: 0xFFFBF8)
    static let stage = Color(hex: 0xFFF9F5)
    static let footer = Color(hex: 0xFFFCFA)
    static let hairline = Color(hex: 0xEFE7E1)
    static let separator = Color(hex: 0xF5EDE8)
    static let barLine = Color(hex: 0xF3E9E2)
    static let track = Color(hex: 0xF4EBE5)
    static let ink = Color(hex: 0x241C18)
    static let rowInk = Color(hex: 0x57483F)
    static let muted = Color(hex: 0x8C7D75)
    static let tertiary = Color(hex: 0xA3948C)
    static let caption = Color(hex: 0xB0A29A)
    static let shade = Color(hex: 0x4B2814)  // shadow tint
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The design's macOS size, or its touch-sized iOS counterpart.
func pt(_ mac: CGFloat, _ touch: CGFloat) -> CGFloat {
    #if os(macOS)
    return mac
    #else
    return touch
    #endif
}

extension View {
    /// Fill plus 1pt hairline: the chrome of cards and small controls.
    func boxed(_ radius: CGFloat, fill: Color = .white, border: Color = Theme.hairline) -> some View {
        background(fill, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(border))
    }
}

/// Text/Layout tabs (`tab`), or the orange pill segments in inspector rows.
struct Segmented<T: CaseIterable & Hashable & RawRepresentable>: View where T.RawValue == String {
    @Binding var selection: T
    var tab = false

    var body: some View {
        HStack(spacing: tab ? 4 : 3) {
            ForEach(Array(T.allCases), id: \.self) { option in
                let on = option == selection
                Button { selection = option } label: {
                    Text(option.rawValue.capitalized)
                        .font(.system(size: tab ? pt(12.5, 15) : pt(11, 13), weight: .semibold))
                        .foregroundStyle(on ? (tab ? Theme.accentInk : .white) : Theme.muted)
                        .padding(.horizontal, tab ? 0 : pt(9, 11))
                        .frame(maxWidth: tab ? .infinity : nil, minHeight: tab ? pt(29, 38) : pt(24, 34))
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: tab ? pt(8, 10) : pt(6, 8))
                                    .fill(tab ? .white : Theme.accent)
                                    .shadow(color: Theme.shade.opacity(tab ? 0.16 : 0), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.track, in: .rect(cornerRadius: tab ? pt(11, 13) : pt(9, 11)))
        .animation(.easeInOut(duration: 0.18), value: selection)
    }
}

/// − / + stepper drawn to the design; VoiceOver still gets a real Stepper.
struct Nudge<V: Strideable>: View {
    let title: String
    @Binding var value: V
    let range: ClosedRange<V>
    let label: String
    var step: V.Stride = 1
    var labelBetween = false  // − label + (copies) instead of label − +
    var side = pt(24, 36)
    var fill = Theme.inspector
    var fontSize = pt(12.5, 15)

    var body: some View {
        HStack(spacing: pt(7, 8)) {
            if !labelBetween { text }
            button("−", by: -step)
            if labelBetween { text }
            button("+", by: step)
        }
        .accessibilityRepresentation { Stepper(title, value: $value, in: range, step: step) }
    }

    private var text: some View {
        Text(label).font(.system(size: fontSize, weight: .semibold)).monospacedDigit().frame(minWidth: 18)
    }

    private func button(_ glyph: String, by n: V.Stride) -> some View {
        let next = value.advanced(by: n)
        return Button { value = next } label: {
            Text(glyph)
                .font(.system(size: fontSize))
                .frame(width: side, height: side)
                .boxed(side * 0.28, fill: fill)  // radius 7 / 10 / 12 at 24 / 36 / 44
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!range.contains(next))
    }
}

/// Print, and Connect on iOS: white on orange, peach when disabled.
struct FilledButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: pt(13, 17), weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .frame(height: pt(36, 52))
            .background {
                RoundedRectangle(cornerRadius: pt(10, 14))
                    .fill(isEnabled ? Theme.accent : Theme.disabled)
                    .shadow(color: Theme.accent.opacity(isEnabled ? 0.4 : 0), radius: 6, y: 5)
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Orange text on a peach wash: Connect on macOS (`bordered`) and the Font value.
struct TintedButton: ButtonStyle {
    var bordered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: pt(12.5, 15), weight: .semibold))
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, bordered ? 16 : pt(11, 13))
            .padding(.vertical, bordered ? 9 : pt(5, 7))
            .boxed(bordered ? 10 : pt(8, 10), fill: configuration.isPressed ? Theme.washPressed : Theme.wash,
                   border: bordered ? Theme.buttonBorder : .clear)
    }
}

/// White outlined chip: B / I / U (`on` when the style is active) and Insert Icon.
struct ChipButton: ButtonStyle {
    var on = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: pt(12.5, 15), weight: .semibold))
            .foregroundStyle(on ? Theme.accentInk : Theme.rowInk)
            .frame(minWidth: pt(30, 44), minHeight: pt(28, 44))
            .boxed(pt(8, 12), fill: on || configuration.isPressed ? Theme.washActive : .white)
            .opacity(isEnabled ? 1 : 0.5)
    }
}
