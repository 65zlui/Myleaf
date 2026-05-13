import SwiftUI

struct EditorView: View {
    @Binding var sourceText: String

    var body: some View {
        TextEditor(text: $sourceText)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(4)
            .frame(minWidth: 350)
    }
}
