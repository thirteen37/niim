import CoreText
import NiimKit
import SwiftUI

struct FontChoice: Hashable {
    var family = "Helvetica"
    var google = false
    var bold = true
}

enum Pane: String, CaseIterable {
    case text = "Text", layout = "Layout"
}

struct ContentView: View {
    static let maxSections = 6

    @State private var printer = Printer()
    @State private var pane = Pane.text
    @State private var texts = ["Hello"] + Array(repeating: "", count: maxSections - 1)
    @State private var sections = 1
    @State private var repeatText = true
    @State private var orientation = LabelOrientation.landscape
    @State private var alignment = LabelAlignment.center
    @State private var wrap = true
    @State private var sizeAdjust = 0.0
    @State private var copies = 1
    @State private var choice = FontChoice()
    @State private var font: CTFontDescriptor?
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
                font = choice.google ? try await GoogleFonts.font(family: choice.family, bold: choice.bold)
                    : systemFont(family: choice.family, bold: choice.bold)
            } catch { self.error = error.localizedDescription }
        }
        .task {
            do {
                (icons, iconFonts) = try await FontAwesome.load()
                emoji = try await GoogleFonts.font(family: "Noto Emoji", bold: false)
            } catch { self.error = error.localizedDescription }
        }
        .sheet(isPresented: $showFonts) { FontPicker(choice: $choice) }
        .sheet(isPresented: $showIcons) {
            IconPicker(icons: icons, fonts: iconFonts) { texts[repeatText ? 0 : min(lastField, sections - 1)].append($0) }
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
                    TextEditor(text: $texts[i])  // Return inserts a line break
                        .font(fieldFont)
                        .frame(minHeight: 60)
                        .focused($focused, equals: i)
                }
            }
            Button("Insert Icon…") { showIcons = true }
                .disabled(icons.isEmpty)
        }
        Section {
            LabeledContent("Font") {
                Button(choice.family) { showFonts = true }
            }
            Toggle("Bold", isOn: $choice.bold)
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

    private var statusLine: String {
        var parts = [printer.status]
        if let label = printer.label { parts.append("\(label.lengthMm.formatted()) × \(label.widthMm.formatted()) mm") }
        if let rfid = printer.rfid { parts.append("\(rfid.total - rfid.used) left") }
        return parts.joined(separator: " · ")
    }

    private var sectionTexts: [String] {
        repeatText ? Array(repeating: texts[0], count: sections) : Array(texts.prefix(sections))
    }

    private var style: TextStyle {
        TextStyle(font: font ?? systemFont(family: choice.family, bold: choice.bold), fallbacks: iconFonts, emoji: emoji,
                  alignment: alignment, wrap: wrap, sizeAdjust: sizeAdjust)
    }

    private func bitmap(_ label: LabelSpec) -> Bitmap {
        Bitmap.label(sectionTexts, spec: label, orientation: orientation, style: style)
    }

    /// System font with Font Awesome as fallback, so inserted icons show in the field instead of boxes.
    private var fieldFont: Font {
        let sys = CTFontCreateUIFontForLanguage(.system, 0, nil)!
        let desc = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(sys), [kCTFontCascadeListAttribute as String: iconFonts] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(desc, CTFontGetSize(sys), nil))
    }
}
