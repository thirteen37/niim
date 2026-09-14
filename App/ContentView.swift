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

enum TextFormat {
    case bold, italic, underline
}

struct ContentView: View {
    static let maxSections = 6

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
        VStack(spacing: 0) {
            header
            Picker("Pane", selection: $pane) {
                ForEach(Pane.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            Form {
                switch pane {
                case .text: textPane
                case .layout: layoutPane
                }
            }
            .formStyle(.grouped)
        }
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

    /// Pinned: preview, printer status and Print.
    private var header: some View {
        VStack(spacing: 10) {
            if let label = printer.label, let image = bitmap(label).cgImage {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .border(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: 280)
            } else {
                ContentUnavailableView(printer.status, systemImage: "printer", description: Text("Turn on the D110 to see a preview."))
                    .frame(height: 180)
            }
            HStack {
                Text(statusLine).font(.callout).foregroundStyle(.secondary)
                Spacer()
                if !printer.isReady {
                    Button("Connect") { printer.connect() }
                }
                Stepper("×\(copies)", value: $copies, in: 1...99)
                    .fixedSize()
                    .accessibilityLabel("Copies")
                Button(printer.isBusy ? "Printing…" : "Print") {
                    guard let label = printer.label else { return }
                    let bmp = bitmap(label).forPrinting(orientation)
                    Task {
                        do { try await printer.printLabel(bmp, quantity: copies) } catch { self.error = error.localizedDescription }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(printer.label == nil || printer.isBusy)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }

    @ViewBuilder private var textPane: some View {
        Section {
            ForEach(0..<(repeatText ? 1 : sections), id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    if !repeatText, sections > 1 {
                        Text("Section \(i + 1)").font(.caption).foregroundStyle(.secondary)
                    }
                    TextEditor(text: $texts[i], selection: $selections[i])  // rich text; Return inserts a line break
                        .font(fieldFont)
                        .frame(minHeight: 60)
                        .focused($focused, equals: i)
                }
            }
            HStack {
                // the app has no Format menu, so the editor's own ⌘B/I/U do nothing; route them through format()
                Button { format(.bold) } label: { Image(systemName: "bold") }.accessibilityLabel("Bold").keyboardShortcut("b")
                Button { format(.italic) } label: { Image(systemName: "italic") }.accessibilityLabel("Italic").keyboardShortcut("i")
                Button { format(.underline) } label: { Image(systemName: "underline") }.accessibilityLabel("Underline").keyboardShortcut("u")
                Spacer()
                Button("Insert Icon…") { showIcons = true }
                    .disabled(icons.isEmpty)
            }
            .buttonStyle(.bordered)
        }
        Section {
            LabeledContent("Font") {
                Button(choice.family) { showFonts = true }
            }
            Picker("Alignment", selection: $alignment) {
                Image(systemName: "text.alignleft").accessibilityLabel("Left").tag(LabelAlignment.left)
                Image(systemName: "text.aligncenter").accessibilityLabel("Center").tag(LabelAlignment.center)
                Image(systemName: "text.alignright").accessibilityLabel("Right").tag(LabelAlignment.right)
            }
            .pickerStyle(.segmented)
            Toggle("Wrap automatically", isOn: $wrap)
            Stepper(value: $sizeAdjust, in: -30...30) {
                LabeledContent("Size", value: sizeAdjust == 0 ? "Auto" : "Auto \(sizeAdjust > 0 ? "+" : "−")\(Int(abs(sizeAdjust))) pt")
            }
        }
    }

    @ViewBuilder private var layoutPane: some View {
        Section {
            Picker("Orientation", selection: $orientation) {
                Image(systemName: "rectangle").accessibilityLabel("Landscape").tag(LabelOrientation.landscape)
                Image(systemName: "rectangle.portrait").accessibilityLabel("Portrait").tag(LabelOrientation.portrait)
            }
            .pickerStyle(.segmented)
            Stepper("Sections: \(sections)", value: $sections, in: 1...Self.maxSections)
            if sections > 1 {
                Toggle("Same text in each", isOn: $repeatText)
            }
        }
    }

    private var activeField: Int { repeatText ? 0 : min(lastField, sections - 1) }

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
        let sys = CTFontCreateUIFontForLanguage(.system, 0, nil)!
        let desc = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(sys), [kCTFontCascadeListAttribute as String: iconFonts] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(desc, CTFontGetSize(sys), nil))
    }
}
