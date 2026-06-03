import NexusSessionPresentation

struct StructuredSessionComposerDraftState: Equatable {
    private(set) var draft = ""
    private var lastObservedEditorText: String?

    mutating func observe(editorText: String?) {
        defer { lastObservedEditorText = editorText }

        guard lastObservedEditorText != editorText,
              let editorText else {
            return
        }

        draft = editorText
    }

    mutating func updateDraft(_ draft: String) {
        self.draft = draft
    }

    mutating func apply(_ command: StructuredSessionSlashCommand) {
        draft = applyStructuredSessionSlashCommand(command, to: draft)
    }

    mutating func clear() {
        draft = ""
    }
}
