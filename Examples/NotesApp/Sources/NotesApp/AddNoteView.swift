import LocalFirstRAG
import SwiftUI

/// Demonstrates the `spotlightVisible` privacy control: unchecking "Include
/// in Spotlight & Siri" means this note is embedded and stored for in-app
/// search as normal, but is never handed to Core Spotlight and never
/// surfaced through `SearchLocalIndexIntent`.
struct AddNoteView: View {
    let index: LocalIndex
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var noteBody = ""
    @State private var spotlightVisible = true
    @State private var saveError: Error?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextEditor(text: $noteBody).frame(minHeight: 160)
                Toggle("Include in Spotlight & Siri", isOn: $spotlightVisible)
                if let saveError {
                    Text("Couldn't save: \(saveError.localizedDescription)")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("New Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(title.isEmpty || noteBody.isEmpty)
                }
            }
        }
    }

    private func save() async {
        do {
            try await index.add(
                id: title,
                text: noteBody,
                spotlightVisible: spotlightVisible
            )
            onSaved()
            dismiss()
        } catch {
            saveError = error
        }
    }
}
