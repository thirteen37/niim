import CoreText
import NiimKit
import SwiftUI

struct FontChoice: Hashable {
    var family = "Helvetica"
    var google = false
    var bold = true
}

struct ContentView: View {
    static let maxSections = 6

    @State private var printer = Printer()
    @State private var texts = ["Hello"] + Array(repeating: "", count: maxSections - 1)
    @State private var sections = 1
    @State private var repeatText = true
    @State private var orientation = LabelOrientation.landscape
    @State private var alignment = LabelAlignment.center
    @State private var wrap = true
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
        Form {
            Section("Printer") {
                LabeledContent("Status", value: printer.status)
                if let label = printer.label {
                    LabeledContent("Label", value: "\(label.lengthMm.formatted()) × \(label.widthMm.formatted()) mm")
                }
                if let rfid = printer.rfid {
                    LabeledContent("Labels left", value: "\(rfid.total - rfid.used) of \(rfid.total)")
                }
                if !printer.isReady {
                    Button("Connect") { printer.connect() }
                }
            }

            Section("Layout") {
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

            Section("Text") {
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
                Toggle("Wrap automatically", isOn: $wrap)
                Picker("Alignment", selection: $alignment) {
                    Image(systemName: "text.alignleft").accessibilityLabel("Left").tag(LabelAlignment.left)
                    Image(systemName: "text.aligncenter").accessibilityLabel("Center").tag(LabelAlignment.center)
                    Image(systemName: "text.alignright").accessibilityLabel("Right").tag(LabelAlignment.right)
                }
                .pickerStyle(.segmented)
                LabeledContent("Font") {
                    Button(choice.family) { showFonts = true }
                }
                Toggle("Bold", isOn: $choice.bold)
                Button("Insert Icon…") { showIcons = true }
                    .disabled(icons.isEmpty)
            }

            if let label = printer.label, let image = bitmap(label).cgImage {
                Section("Preview") {
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: orientation == .portrait ? 320 : nil)
                        .border(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            Section {
                Button(printer.isBusy ? "Printing…" : "Print") {
                    guard let label = printer.label else { return }
                    let bmp = bitmap(label).forPrinting(orientation)
                    Task {
                        do { try await printer.printLabel(bmp) } catch { self.error = error.localizedDescription }
                    }
                }
                .disabled(printer.label == nil || printer.isBusy)
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
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

    private var sectionTexts: [String] {
        repeatText ? Array(repeating: texts[0], count: sections) : Array(texts.prefix(sections))
    }

    private var style: TextStyle {
        TextStyle(font: font ?? systemFont(family: choice.family, bold: choice.bold), fallbacks: iconFonts, emoji: emoji, alignment: alignment, wrap: wrap)
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
