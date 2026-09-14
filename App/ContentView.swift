import NiimKit
import SwiftUI

struct ContentView: View {
    @State private var printer = Printer()
    @State private var text = "Hello"
    @State private var fontSize = 32.0
    @State private var error: String?

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

            Section("Label") {
                TextField("Text", text: $text, axis: .vertical)
                LabeledContent("Size") { Slider(value: $fontSize, in: 12...80) }
                if let label = printer.label, let image = bitmap(label).cgImage {
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .border(.secondary)
                }
            }

            Section {
                Button(printer.isBusy ? "Printing…" : "Print") {
                    guard let label = printer.label else { return }
                    Task {
                        do { try await printer.printLabel(bitmap(label).rotatedCW()) } catch { self.error = error.localizedDescription }
                    }
                }
                .disabled(printer.label == nil || printer.isBusy)
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .onAppear { printer.connect() }
    }

    private func bitmap(_ label: LabelSpec) -> Bitmap {
        Bitmap.landscape(text, spec: label, fontSize: fontSize)
    }
}
