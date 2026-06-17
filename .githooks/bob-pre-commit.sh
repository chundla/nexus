# Bob Shell pre-commit: filter stale pending notes (see .bob/notes).
# Sourced from .githooks/pre-commit when .bob exists.

filter_notes_by_modified_files() {
    local NOTES_FILE="$1"
    local ALL_MODIFIED="$2"

    if [ ! -f "$NOTES_FILE" ] || [ ! -s "$NOTES_FILE" ]; then
        return
    fi

    local REPO_ROOT
    REPO_ROOT=$(git rev-parse --show-toplevel)

    local FILTERED_NOTES
    FILTERED_NOTES=$(mktemp)
    while IFS= read -r line; do
        local FILE_PATH
        FILE_PATH=$(echo "$line" | grep -o '"path":"[^"]*"' | cut -d'"' -f4)
        local RELATIVE_PATH="${FILE_PATH#$REPO_ROOT/}"
        if echo "$ALL_MODIFIED" | grep -qF "$RELATIVE_PATH"; then
            echo "$line" >> "$FILTERED_NOTES"
        fi
    done < "$NOTES_FILE"

    if [ -s "$FILTERED_NOTES" ]; then
        mv "$FILTERED_NOTES" "$NOTES_FILE"
    else
        : >"$NOTES_FILE"
        rm -f "$FILTERED_NOTES"
    fi
}

run_bob_pre_commit() {
    local NOTES_FILE=".bob/notes/pending-notes.txt"
    local STAGED_FILES UNSTAGED_FILES UNTRACKED_FILES ALL_MODIFIED

    STAGED_FILES=$(git diff --cached --name-only 2>/dev/null)
    UNSTAGED_FILES=$(git diff --name-only 2>/dev/null)
    UNTRACKED_FILES=$(git ls-files --others --exclude-standard 2>/dev/null)
    ALL_MODIFIED=$(printf '%s\n' "$STAGED_FILES" "$UNSTAGED_FILES" "$UNTRACKED_FILES" | sort -u)

    filter_notes_by_modified_files "$NOTES_FILE" "$ALL_MODIFIED"
}