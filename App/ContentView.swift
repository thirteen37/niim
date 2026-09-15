import CoreText
import NiimKit
import SwiftUI

struct FontChoice: Hashable, Codable {
    var family = "Helvetica"
    var google = false
}

enum Pane: String, CaseIterable {
    case text = "Text", layout = "Layout"
}

enum TextFormat: String, CaseIterable {
    case bold, italic, underline  // SF Symbol names
}

struct ContentView: View {
    static let maxSections = 6
    static let estimate = LabelSpec(lengthMm: 40, widthMm: 12)  // previewed until the printer reports its roll

    @Environment(\.fontResolutionContext) private var fontContext
    @State private var printer = Printer()
    @State private var pane = Pane.text
    @State private var texts = [AttributedString("Hello")] + Array(repeating: AttributedString(), count: maxSections - 1)
    @State private var selections = Array(repeating: AttributedTextSelection(), count: maxSections)
    @State private var sections = 1
    @State private var repeatText = true
    @State private var orientation = LabelOrientation.landscape
    @State private var alignment = LabelAlignment.center
    @State private var wrap = true
    @State private var sizeAdjust = 0.0
    @State private var copies = 1
    @State private var choice = FontChoice()
    @State private var faces: FontFaces?
    @State private var icons: [Icon] = []
    @State private var iconFonts: [CTFontDescriptor] = []
    @State private var emoji: CTFontDescriptor?
    @State private var showFonts = false
    @State private var showIcons = false
    @State private var error: String?
    @FocusState private var focused: Int?
    @State private var lastField = 0

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 820 { wide } else { compact }
        }
        .background(Theme.window)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .preferredColorScheme(.light)  // the palette is light-only
        .onAppear { printer.connect() }
        .onChange(of: focused) { _, field in
            if let field { lastField = field }
        }
        .task(id: choice) {
            do {
                faces = choice.google ? try await GoogleFonts.faces(family: choice.family) : .system(family: choice.family)
            } catch { self.error = error.localizedDescription }
        }
        .task {
            do {
                (icons, iconFonts) = try await FontAwesome.load()
                emoji = try await GoogleFonts.font(family: "Noto Emoji", bold: false, italic: false)
            } catch { self.error = error.localizedDescription }
        }
        .sheet(isPresented: $showFonts) { FontPicker(choice: $choice) }
        .sheet(isPresented: $showIcons) {
            IconPicker(icons: icons, fonts: iconFonts) { texts[activeField].append(AttributedString(String($0))) }
        }
    }

    /// Mac window and iPad landscape: preview stage + action bar on the left, inspector on the right.
    private var wide: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 22) {
                    HStack(spacing: 8) {
                        pulseDot(7)
                        Text(statusLine).font(.system(size: 12, weight: .semibold)).tracking(0.24).foregroundStyle(Theme.accentInk)
                    }
                    .padding(.vertical, 6).padding(.leading, 10).padding(.trailing, 13)
                    .background(Theme.washActive, in: .capsule)
                    .overlay(Capsule().strokeBorder(Theme.washBorder))
                    VStack(spacing: 9) {
                        previewCard("Label preview")
                        previewNote
                    }
                    .frame(maxWidth: 640)
                    if !printer.isReady {
                        Text("Turn on the D110 and keep it nearby. NIIM connects over Bluetooth automatically.")
                            .font(.system(size: 13.5)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center).frame(maxWidth: 370)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LinearGradient(stops: [.init(color: Theme.stage, location: 0), .init(color: Theme.window, location: 0.62)],
                                           startPoint: .top, endPoint: .bottom))
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        if !printer.isReady {
                            Button("Connect") { printer.connect() }.buttonStyle(TintedButton(bordered: true))
                        }
                        Spacer()
                        HStack(spacing: 7) {
                            Text("Copies").font(.system(size: pt(12, 15))).foregroundStyle(Theme.muted)
                            Nudge(title: "Copies", value: $copies, range: 1...99, label: "\(copies)", labelBetween: true,
                                  fontSize: pt(13, 16))
                        }
                        .padding(4).padding(.leading, 7)
                        .boxed(10)
                        printButton(fullWidth: false)
                    }
                    errorLine
                }
                .padding(.vertical, 13).padding(.horizontal, 18)
                .overlay(alignment: .top) { Theme.hairline.frame(height: 1) }
            }
            .overlay(alignment: .trailing) { Theme.hairline.frame(width: 1) }
            VStack(spacing: 0) {
                Segmented(selection: $pane, tab: true).padding([.top, .horizontal], 16)
                ScrollView { panes.padding(16) }
            }
            .frame(width: 348)
            .background(Theme.inspector)
        }
    }

    /// iPhone and narrow windows: header, scrolling preview + panes, print bar.
    private var compact: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("NIIM").font(.system(size: 17, weight: .bold)).tracking(1)
                pulseDot(6)
                Text(printer.status).font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                Spacer()
            }
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(Theme.stage)
            .overlay(alignment: .bottom) { Theme.barLine.frame(height: 1) }
            ScrollView {
                VStack(spacing: 16) {
                    previewCard("Preview", note: true)
                    Segmented(selection: $pane, tab: true)
                    panes
                }
                .padding(16)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if printer.isReady {
                        Nudge(title: "Copies", value: $copies, range: 1...99, label: "×\(copies)", labelBetween: true,
                              side: pt(24, 44), fill: .white, fontSize: pt(13, 16))
                        printButton(fullWidth: true)
                    } else {  // there is no printing without connecting
                        Button { printer.connect() } label: { Text("Connect").frame(maxWidth: .infinity) }
                            .buttonStyle(FilledButton())
                    }
                }
                errorLine
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.stage)
            .overlay(alignment: .top) { Theme.barLine.frame(height: 1) }
        }
    }

    /// The real bitmap inside a dashed tape edge at the label's true proportions.
    private func previewCard(_ title: String, note: Bool = false) -> some View {
        let spec = printer.label ?? Self.estimate
        let (l, w) = (spec.lengthMm.formatted(), spec.widthMm.formatted())
        let portrait = orientation == .portrait
        return VStack(alignment: .leading, spacing: pt(12, 11)) {
            HStack {
                Text(title)
                Spacer()
                Text("\(orientation.rawValue) · \(portrait ? "\(w) × \(l)" : "\(l) × \(w)") mm")
            }
            .font(.system(size: pt(11, 10.5), weight: .semibold)).textCase(.uppercase).tracking(1).foregroundStyle(Theme.tertiary)
            if let image = bitmap(spec).cgImage {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: pt(12, 13)))
                    .overlay(RoundedRectangle(cornerRadius: pt(12, 13)).strokeBorder(Theme.disabled, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                    .frame(height: portrait ? pt(300, 260) : nil)
                    .frame(maxWidth: .infinity)
            }
            if note { previewNote }
        }
        .padding(pt(16, 14))
        .background {
            RoundedRectangle(cornerRadius: pt(18, 20)).fill(.white)
                .shadow(color: Theme.shade.opacity(0.14), radius: 14, y: 12)
        }
        .overlay(RoundedRectangle(cornerRadius: pt(18, 20)).strokeBorder(Theme.hairline))
    }

    private var previewNote: some View {
        Text(printer.label == nil ? "Estimated on 12 mm tape · connect the D110 to confirm"
             : wrap ? "Text wraps to fit the tape" : "Wrapping off · text shrinks to fit")
            .font(.system(size: 11)).foregroundStyle(Theme.caption)
    }

    private func printButton(fullWidth: Bool) -> some View {
        Button {
            guard let label = printer.label else { return }
            let bmp = bitmap(label).forPrinting(orientation)
            Task {
                do { try await printer.printLabel(bmp, quantity: copies) } catch { self.error = error.localizedDescription }
            }
        } label: {
            Text(printer.isBusy ? "Printing…" : "Print").frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .buttonStyle(FilledButton())
        .disabled(printer.label == nil || printer.isBusy)
    }

    @ViewBuilder private var errorLine: some View {
        if let error { Text(error).font(.system(size: 13)).foregroundStyle(.red) }
    }

    private func pulseDot(_ size: CGFloat) -> some View {
        // a symbol effect, not phaseAnimator: its always-running animation also slid the dot when the layout moved
        Image(systemName: "circle.fill").font(.system(size: size)).foregroundStyle(Theme.accent).symbolEffect(.breathe)
    }

    @ViewBuilder private var panes: some View {
        switch pane {
        case .text: textPane
        case .layout: layoutPane
        }
    }

    private var textPane: some View {
        VStack(spacing: pt(13, 16)) {
            VStack(spacing: 0) {
                ForEach(0..<(repeatText ? 1 : sections), id: \.self) { i in
                    if i > 0 { Theme.separator.frame(height: 1) }
                    VStack(alignment: .leading, spacing: 4) {
                        if !repeatText, sections > 1 {
                            Text("Section \(i + 1)").font(.caption).foregroundStyle(Theme.tertiary)
                        }
                        TextEditor(text: $texts[i], selection: $selections[i])  // rich text; Return inserts a line break
                            .font(fieldFont)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: pt(63, 74))
                            .focused($focused, equals: i)
                            #if os(macOS)
                            // type straight away; .defaultFocus loses to the tab bar, and iOS would raise the keyboard
                            .task { if i == 0, focused == nil { focused = 0 } }
                            #endif
                    }
                    .padding(.vertical, pt(12, 14)).padding(.horizontal, pt(13, 14))
                }
                HStack(spacing: pt(6, 8)) {
                    // the app has no Format menu, so the editor's own ⌘B/I/U do nothing; route them through format()
                    ForEach(TextFormat.allCases, id: \.self) { f in
                        Button { format(f) } label: { Image(systemName: f.rawValue) }
                            .buttonStyle(ChipButton(on: isOn(f)))
                            .accessibilityLabel(f.rawValue.capitalized)
                            .keyboardShortcut(KeyEquivalent(f.rawValue.first!))
                    }
                    Spacer()
                    Button { showIcons = true } label: { Text("Insert Icon…").padding(.horizontal, pt(12, 14)) }
                        .buttonStyle(ChipButton())
                        .disabled(icons.isEmpty)
                }
                .padding(pt(8, 10))
                .background(Theme.footer)
                .overlay(alignment: .top) { Theme.separator.frame(height: 1) }
            }
            .clipShape(.rect(cornerRadius: pt(14, 16)))
            .boxed(pt(14, 16))

            VStack(spacing: 0) {
                row("Font") {
                    Button(choice.family) { showFonts = true }.buttonStyle(TintedButton())
                }
                row("Alignment") { Segmented(selection: $alignment) }
                row("Wrap automatically") { Toggle("Wrap automatically", isOn: $wrap).toggleStyle(.switch).labelsHidden() }
                row("Size", last: true) {
                    // printer dots added to the auto-fit size, so not labelled as points
                    Nudge(title: "Size", value: $sizeAdjust, range: -30...30,
                          label: sizeAdjust == 0 ? "Auto" : "\(sizeAdjust > 0 ? "+" : "−")\(Int(abs(sizeAdjust)))", step: 2)
                }
            }
            .padding(.horizontal, pt(13, 14))
            .boxed(pt(14, 16))
        }
    }

    private var layoutPane: some View {
        VStack(spacing: 0) {
            row("Orientation") { Segmented(selection: $orientation) }
            row("Sections", last: sections == 1) {
                Nudge(title: "Sections", value: $sections, range: 1...Self.maxSections, label: "\(sections)")
            }
            if sections > 1 {
                row("Same text in each", last: true) {
                    Toggle("Same text in each", isOn: $repeatText).toggleStyle(.switch).labelsHidden()
                }
            }
        }
        .padding(.horizontal, pt(13, 14))
        .boxed(pt(14, 16))
    }

    /// Inspector row: label left, control right, separator below unless `last`.
    private func row(_ title: String, last: Bool = false, @ViewBuilder _ control: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: pt(13, 16))).foregroundStyle(Theme.rowInk)
            Spacer()
            control()
        }
        .padding(.vertical, pt(11, 13))
        .overlay(alignment: .bottom) { if !last { Theme.separator.frame(height: 1) } }
    }

    private var activeField: Int { repeatText ? 0 : min(lastField, sections - 1) }

    /// Whether the style is on at the last-edited section's cursor, for the B/I/U highlight.
    private func isOn(_ f: TextFormat) -> Bool {
        let c = selections[activeField].typingAttributes(in: texts[activeField])
        let font = (c.font ?? .default).resolve(in: fontContext)
        switch f {
        case .bold: return font.isBold
        case .italic: return font.isItalic
        case .underline: return c.underlineStyle != nil
        }
    }

    /// Toggles a style on the selection (or typing attributes) of the last-edited section.
    private func format(_ f: TextFormat) {
        let i = activeField
        texts[i].transformAttributes(in: &selections[i]) { c in
            switch f {
            case .bold:
                let font = c.font ?? .default
                c.font = font.bold(!font.resolve(in: fontContext).isBold)
            case .italic:
                let font = c.font ?? .default
                c.font = font.italic(!font.resolve(in: fontContext).isItalic)
            case .underline:
                c.underlineStyle = c.underlineStyle == nil ? .single : nil
            }
        }
    }

    /// Editor runs → label spans. Bold/italic come from the run's font, or Markdown-style intents.
    private func spans(_ s: AttributedString) -> [TextRun] {
        s.runs.map { run in
            let font = (run.font ?? .default).resolve(in: fontContext)
            let intent = run.inlinePresentationIntent ?? []
            return TextRun(String(s[run.range].characters),
                        bold: font.isBold || intent.contains(.stronglyEmphasized),
                        italic: font.isItalic || intent.contains(.emphasized),
                        underline: run.underlineStyle != nil)
        }
    }

    private var statusLine: String {
        var parts = [printer.status]
        if let label = printer.label { parts.append("\(label.lengthMm.formatted()) × \(label.widthMm.formatted()) mm") }
        if let rfid = printer.rfid { parts.append("\(rfid.total - rfid.used) left") }
        return parts.joined(separator: " · ")
    }

    private var sectionTextRuns: [[TextRun]] {
        repeatText ? Array(repeating: spans(texts[0]), count: sections) : texts.prefix(sections).map(spans)
    }

    private var style: TextStyle {
        TextStyle(faces: faces ?? .system(family: choice.family), fallbacks: iconFonts, emoji: emoji,
                  alignment: alignment, wrap: wrap, sizeAdjust: sizeAdjust)
    }

    private func bitmap(_ label: LabelSpec) -> Bitmap {
        Bitmap.label(sectionTextRuns, spec: label, orientation: orientation, style: style)
    }

    /// System font with Font Awesome as fallback, so inserted icons show in the field instead of boxes.
    private var fieldFont: Font {
        let sys = CTFontCreateUIFontForLanguage(.system, pt(14, 17), nil)!
        let desc = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(sys), [kCTFontCascadeListAttribute as String: iconFonts] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(desc, CTFontGetSize(sys), nil))
    }
}
