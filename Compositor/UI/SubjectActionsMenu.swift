import SwiftUI

struct SubjectLayerCommands: View {
    let session: EditorSession

    var body: some View {
        ForEach(SubjectRegion.allCases, id: \.self) { region in
            Button(zh(region.layerName)) { Task { await session.extractSubjectLayers(region) } }
                .disabled(!session.canExtractSubjectLayers)
        }
        Button(zh("Separate Subject and Background")) { Task { await session.extractSubjectLayers(nil) } }
            .disabled(!session.canExtractSubjectLayers || (session.document?.layers.count ?? 10_000) > 9_998)
    }
}

/// The same actions are available from the Layer menu and the Layers panel.
struct SubjectActionsMenu: View {
    let session: EditorSession

    var body: some View {
        Menu {
            SubjectLayerCommands(session: session)
            Divider()
            ForEach(SubjectRegion.allCases, id: \.self) { region in
                Button(zh(region.selectionName)) { Task { await session.selectSubject(region: region) } }
                    .disabled(!session.canSelectSubject)
            }
        } label: {
            Label(zh("AI Subject & Background"), systemImage: "person.crop.rectangle")
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .help(zh("Extract from one image layer on this Mac. New layers keep editable masks; the original is kept hidden."))
        .accessibilityIdentifier("subjectActions")
        .padding(.horizontal, 18).padding(.vertical, 10)
    }
}
