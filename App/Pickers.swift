import CoreText
import NiimKit
import SwiftUI

struct FontPicker: View {
    @Binding var choice: FontChoice
    @Environment(\.dismiss) private var dismiss
    @State private var google = false
    @State private var query = ""
    @State private var system: [String] = []
    @State private var googleFamilies: [GoogleFamily] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Picker("Source", selection: $google) {
                    Text("System").tag(false)
                    Text("Google Fonts").tag(true)
                }
                .pickerStyle(.segmented)
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(names, id: \.self) { name in
                    Button {
                        choice = FontChoice(family: name, google: google)
                        dismiss()
                    } label: {
                        HStack {
                            // Google families aren't downloaded until picked, so only system ones preview in their own face
                            Text(name).font(google ? .body : .custom(name, size: 17))
                            Spacer()
                            if choice.family == name, choice.google == google { Image(systemName: "checkmark") }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "Search fonts")
            .navigationTitle("Font")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                google = choice.google
                system = systemFontFamilies()
                do { googleFamilies = try await GoogleFonts.families() } catch { self.error = error.localizedDescription }
            }
        }
        .frame(idealWidth: 420, idealHeight: 560)  // macOS sizes sheets to ideal size; a List alone has none and collapses
    }

    private var names: [String] {
        let all = google ? googleFamilies.map(\.name) : system
        return query.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(query) }
    }
}

struct IconPicker: View {
    let icons: [Icon]
    let fonts: [CTFontDescriptor]  // [Solid, Brands]
    let insert: (Character) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))]) {
                    ForEach(filtered) { icon in
                        Button {
                            insert(icon.character)
                            dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                Text(String(icon.character))
                                    .font(Font(CTFontCreateWithFontDescriptor(fonts[icon.brand ? 1 : 0], 28, nil)))
                                Text(icon.name).font(.caption2).lineLimit(1)
                            }
                            .frame(width: 72, height: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .searchable(text: $query, prompt: "Search icons")
            .navigationTitle("Icons")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var filtered: [Icon] {
        query.isEmpty ? icons : icons.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}
