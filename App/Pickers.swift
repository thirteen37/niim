import CoreText
import NiimKit
import SwiftUI

struct FontPicker: View {
    static let maxRecents = 8

    @Binding var choice: FontChoice
    @Environment(\.dismiss) private var dismiss
    @AppStorage("recentFonts") private var recentData = Data()  // JSON [FontChoice], most recent first
    @State private var google = false
    @State private var query = ""
    @State private var system: [String] = []
    @State private var googleFamilies: [GoogleFamily] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if !recents.isEmpty {
                    Section("Recent") {
                        ForEach(recents, id: \.self) { row($0, showSource: true) }
                    }
                }
                Section {
                    Picker("Source", selection: $google) {
                        Text("System").tag(false)
                        Text("Google Fonts").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if let error { Text(error).foregroundStyle(.red) }
                    ForEach(names, id: \.self) { row(FontChoice(family: $0, google: google), showSource: false) }
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

    private func row(_ font: FontChoice, showSource: Bool) -> some View {
        Button {
            choice = font
            recentData = (try? JSONEncoder().encode(Array(([font] + allRecents.filter { $0 != font }).prefix(Self.maxRecents)))) ?? recentData
            dismiss()
        } label: {
            HStack {
                // Google families aren't downloaded until picked, so only system ones preview in their own face
                Text(font.family).font(font.google ? .body : .custom(font.family, size: 17))
                if showSource, font.google {
                    Text("Google").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if font == choice { Image(systemName: "checkmark") }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var allRecents: [FontChoice] {
        (try? JSONDecoder().decode([FontChoice].self, from: recentData)) ?? []
    }

    /// Recents stay on top and follow the search, so a partial name finds a recent font first.
    private var recents: [FontChoice] {
        query.isEmpty ? allRecents : allRecents.filter { $0.family.localizedCaseInsensitiveContains(query) }
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
