#!/usr/bin/env bash
# Structured Session assistant markdown + feed responsiveness guardrails (#230).
# Narrowest automated regression slice before iPhone/macOS Instruments traces.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== NexusSessionPresentation: markdown renderer + hydration =="
swift test --package-path Modules --filter StructuredSessionMarkdownRendererTests

echo "== NexusSessionPresentation: full-response reader (code blocks) =="
swift test --package-path Modules --filter StructuredSessionAssistantFullResponseReaderTests

echo "== NexusSessionPresentation: assistant markdown policy + idle-gated hydration =="
swift test --package-path Modules --filter 'StructuredSessionPresentationTests/structuredSessionFeedMarkdownParsingIsAssistantOnly'
swift test --package-path Modules --filter 'StructuredSessionPresentationTests/structuredSessionConversationPresentationMarksCommandAndSystemRowsAsNonMarkdown'
swift test --package-path Modules --filter 'StructuredSessionPresentationTests/structuredSessionFeedAssistantMarkdownDisplayPolicyBoundsLongFinalizedResponses'
swift test --package-path Modules --filter 'StructuredSessionPresentationTests/structuredSessionFeedAssistantMarkdownBoundedPreviewTextTruncatesBeforeMarkdownParse'
swift test --package-path Modules --filter 'StructuredSessionPresentationTests/structuredSessionAssistantFullResponsePresentationCarriesRowIDAndMarkdown'
swift test --package-path Modules --filter 'StructuredSessionPresentationTests/structuredSessionFeedPresenterFinalizeKeepsNonEmptyAssistantBodyWhenLongResponseUsesBoundedPreview'
swift test --package-path Modules --filter 'StructuredSessionPresentationTests/structuredSessionFeedAssistantAutoExpandedLatestResponsePrefersPlainTextOnlyForImplicitLatestExpansion'
swift test --package-path Modules --filter 'StructuredSessionPresentationTests/structuredSessionLatestAssistantInlineMarkdownIdleGatePolicyMatchesPlatformExpectations'
swift test --package-path Modules --filter 'StructuredSessionPresentationTests/structuredSessionFeedAllowsLatestAssistantInlineMarkdownHydrationWhenIdleOnIOS'
swift test --package-path Modules --filter 'StructuredSessionPresentationTests/structuredSessionFeedScrollReaderIdleStateRequiresQuietInterval'
swift test --package-path Modules --filter 'StructuredSessionPresentationTests/structuredSessionFeedTailIsStableForInlineMarkdownWhenFollowTokenMatches'
swift test --package-path Modules --filter 'StructuredSessionPresentationTests/structuredSessionFeedPresenterDefersAssistantMarkdownPrewarmUntilAfterPresentationReturns'
swift test --package-path Modules --filter 'StructuredSessionPresentationTests/structuredSessionFeedPresenterPrewarmsFullAssistantMarkdownForLongFinalizedResponses'

echo "== nexusTests: structured feed profiling fixture pre-flight =="
xcodebuild test -scheme nexus -project nexus.xcodeproj -destination 'platform=macOS' \
  -only-testing:nexusTests/RemoteClientProfilingFixtureTests/bootstrapStreamsDeterministicStructuredFeedProfilingBursts \
  -only-testing:nexusTests/NexusAppProfilingFixtureTests/bootstrapStreamsDeterministicStructuredFeedProfilingBurstsOnMacOS

echo "Guardrails passed. For iPhone hitch evidence see docs/structured-session-instruments-harness.md (#230 markdown-heavy workload)."