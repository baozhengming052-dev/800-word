# Personal library implementation plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to execute this plan in the current session.

Goal: Let the owner manually add words and questions, edit/archive/restore them, study them using existing learning features, and exchange them offline with the existing nearby protocol without losing historical answers.
Architecture: Immutable personal-content revisions and existing learning events share a validated v3 snapshot. A pure catalog projects current content and preserves all question revisions. DataManager is the atomic transaction boundary; SwiftUI uses persistent modal draft ownership.
Tech stack: Swift/SwiftUI (iOS 15+), Foundation, existing MultipeerConnectivity transport, Python validation and native Swift executable tests on GitHub macOS.
Spec: docs/superpowers/specs/2026-09-13-personal-library-design.md (user approved).
Execution: Sequential tasks, one implementation agent at a time, task review after each. Work directly in user-selected checkout.

## Global Constraints

- Only edit C:/Users/ASUS/Desktop/花生800词/Words800App. No commits, tags, pushes, remote writes, worktree creation, toolchain installation or Git configuration changes.
- Keep Bundle Identifier com.peanut13.words800, existing TrollStore unsigned packaging and Tag-driven release naming unchanged.
- Built-in PDF/library are read-only. Personal question type is 手动录入, never certified real-exam content.
- Preserve every existing learning event ID and all immutable revision IDs/payloads. Historical answers use exact question revision IDs, not later answers or changed links.
- Use stable word UUIDs for personal questions; resolve built-in string associations against built-in words only.
- No answers, explanations, related-word meanings or notes before submitting a practice answer.
- No API, OCR, cloud, QR, server, image attachments, batch import, permanent deletion or automatic question invention.
- v3 snapshot size <=20,000,000 bytes; events plus personal revisions <=100,000. Each revision encoded <=256 KiB. Word <=80 characters; pinyin/category <=100; other content text <=10,000; options <=2,000 each. Existing event value <=100,000 UTF-8 bytes.
- Fields trim outer whitespace; four nonempty normalized-distinct options, answer explicitly selected in 0...3, at least one unique valid word ID.
- v2 imports merge without clearing personal content. v3 primary/previous files are separate from v2. Damaged v3 must not silently fall back to stale v2.
- No native Swift compiler exists on this Windows host. Write behavioral native tests FIRST, attempt the compiler to record the limitation, and register them for GitHub macOS. Run all locally available Python/project/parser checks; never label these as native build or device success.
- Use apply_patch for edits and preserve unrelated user changes. Existing native UI, light/dark colors, accent, and iPad layout remain.
- No subagents from implementation agents. Controller owns reviews. Review artifacts use working-tree diffs because no commits are authorized.

## Shared interfaces

Task 1 owns final exact naming of core models and documents any small naming adjustment in its report; later tasks consume that report.
- PersonalWordContent: Codable/Equatable, editable word/meaning/pinyin/category/example/keyPoints strings (defaults for optional fields).
- PersonalQuestionContent: Codable/Equatable, editable content/options/correctAnswer/explanation/relatedWordIDs/source. Four initial empty options; correctAnswer initially -1.
- PersonalRevision: Codable/Equatable/Identifiable, immutable id UUID, entryID UUID, parents [UUID], timestamp Double milliseconds, optional word and question payloads (exactly one), archived Bool.
- StudySnapshot: Codable, default schemaVersion 3, events [StudyEvent], revisions [PersonalRevision]. Missing revisions decode only as legacy empty content; unknown versions reject through codec.
- Word.isPersonal and Question.personalEntryID/relatedWordIDs distinguish projections without breaking existing JSON decoding/memberwise initializers. A personal Word.id is entryID; personal Question.id is revision.id.
- PersonalCatalog: all current words including archived (history), all question revisions (history/reducer), activeQuestions, archivedWordIDs, current heads by entry ID. Multi-head provisional projection is deterministic and never silently resolves conflicts.
- PersonalLibrary builds/validates catalog from builtInWords, builtInQuestions and snapshot, normalizes names and input, validates content, detects active-name collisions.
- SnapshotCodec.decode(data:builtInWords:builtInQuestions:now:) throws -> StudySnapshot; validate(snapshot:builtInWords:builtInQuestions:now:) throws -> PersonalCatalog. It validates full personal directory before learning references.
- SnapshotStore(directory:validate:) has load() throws -> StudySnapshot?, save(_:) throws and recoveryMessage. Validation supplied as closure avoids DataManager dependencies.
- LearningEngine.relatedWordIDs(for:words:) -> [UUID] centralizes relationship lookup.

## Task 1: Immutable content, snapshot storage, historical learning

Files:
- Modify Words800App/Models.swift and LearningEngine.swift.
- Create Words800App/PersonalLibrary.swift (split PersonalModels.swift if needed), SnapshotCodec.swift, SnapshotStore.swift.
- Create tests/PersonalLibraryTests.swift and tests/SnapshotStoreTests.swift; extend tests/LearningEngineTests.swift for version-specific scoring.
- Register production files in Words800App.xcodeproj/project.pbxproj and test commands/dependencies in tools/verify_macos.sh.

Consumes: existing bundled Library, StudyEvent and LearningEngine behavior.
Produces: Shared interfaces above, behavior tests, codec/storage independent of SwiftUI/DataManager.

Steps:
- [ ] First add executable @main native tests constructing real content, snapshots, temporary directories and immutable edit chains. Tests must call production interfaces, not grep source.
- [ ] Include assertions: empty fields/duplicate options/unselected answer fail; root/add/edit retain stable word identity; question versions retain old answers and links; word rename retains links; archive/restore affect active catalog not historical question lookup.
- [ ] Include invalid DAG parent/mixed-kind/cycle/duplicate revision IDs/cross-entry parent/missing word/reference/name collision cases. Structural corruption throws; valid concurrent heads and active-name collisions remain inspectable for sync/UI.
- [ ] Include v2 JSON decode/event-ID preservation, v3 roundtrip, unknown schema, malformed event, record/text/data limits, parent ordering independent of time, duplicate built-in names not crashing.
- [ ] Include real SnapshotStore tests for migration preserving v2 bytes, save/reload, primary corruption retaining evidence and recovering previous v3, corrupt primary+backup throwing without v2 rollback, and failed write not advancing in-memory callers.
- [ ] Attempt swiftc; document command-not-found as native verification unavailable, NOT a red test pass. Keep tests registered for real macOS execution.
- [ ] Implement model Codable compatibility. One payload kind per revision; reject identities colliding with built-in IDs or between word/question entry domains and revision/question IDs.
- [ ] Validate revisions in linear/topological passes, not recursive depth-sensitive traversal or quadratic whole-tree scans. Reject parents with duplicates, mixed entry/kind or absent IDs; allow unordered input and multiple roots/heads for later explicit conflict resolution.
- [ ] Validate all historical question payloads against built-in plus personal word entry IDs; project every personal question revision into historical Question records. Current active questions use selected head, nonarchived and active associated-word filtering performed by runtime.
- [ ] Refactor relationship reduction to use UUID links for personal questions and a safely constructed built-in-only name lookup otherwise. Existing events and learning scheduling semantics stay intact.
- [ ] SnapshotCodec accepts schema 2 with no personal revisions and returns schema 3; verifies events with the union catalog. Same immutable duplicate IDs or changed payloads reject. Unresolved semantic content/name conflicts are not decode failures.
- [ ] SnapshotStore writes validated bytes atomically; backup previous valid v3 before primary write; v2 migration writes only new v3; load existing damaged v3 preserves evidence and uses valid previous v3 only.
- [ ] Update every native compile invocation needing Models to include new model/catalog dependencies; keep pure UI-only test invocations independent.
- [ ] Run Python regressions and project checks, inspect Swift source syntax when parser available, self-review and report exact API decisions plus all unavailable checks.

Test example semantics:
```swift
let before = LearningEngine.reduce(words: catalog.words, questions: catalog.questions,
    events: [StudyEvent(kind: "answer", value: "0", questionID: originalQuestionRevision.id)])
// Original answer 1 is wrong; later revision answer 0 must not make this correct.
expect(before.questions.first?.isCorrect == false, "historical result must not change")
```
Adapt actual reducer tuple/property spelling to existing implementation; assert exact original linked word receives the error even after later links change.

## Task 2: Content-aware merge and transport compatibility

Files:
- Modify Words800App/SyncMergeEngine.swift, SyncExchange.swift.
- Extend tests/SyncMergeEngineTests.swift and SyncExchangeTests.swift; create tests/PersonalSyncTests.swift.
- Update tools/verify_macos.sh and project file only if a small pure support file is introduced.

Consumes: Task 1 catalog/revisions/codec, existing learning conflict choices and two-phase sync exchange.
Produces: Content conflicts/preview counts, content resolution entry point, full-record stale-preview validation, capability-checked transport.

Steps:
- [ ] Add tests FIRST for independent words/questions merging; descendant edit automatically active; sibling edit and archive-vs-edit requiring choice; resolution parent set includes all heads; re-sync idempotence.
- [ ] Test same-name independently created words: choose one live ID and archive the other without changing either history/events. Built-in collision can only retain built-in active and archive personal (rename available later in editor).
- [ ] Test foreign snapshot with personal answer references, v2 import preserving personal content, same revision ID changed payload rejection, content-only stale preview rejection, and final proposal retaining every local event/revision byte-equivalently.
- [ ] Test combined count/size ceilings after union or conflict-resolution records. Validate final proposals through SnapshotCodec and refuse unresolved content/name conflicts.
- [ ] Add transport test showing old packet/schema is rejected with upgrade instructions, new same built-in fingerprint/different personal content succeeds.
- [ ] Extend SyncMergePreview with typed content conflicts and content change summary (added/edited/archived word and question entries for either direction), without replacing old note/error conflicts.
- [ ] Union immutable records by UUID and exact equality; reject ID reuse. Snapshot schema after union is 3. Build merged catalog using ORIGINAL bundled arrays passed by DataManager.
- [ ] Compute heads from parent membership. For concurrent heads present options containing full word/question content, archive state and revision IDs. Caller choices use conflict ID -> selected option UUID, not device clock.
- [ ] Implement resolveContent(preview:choices:words:questions:now:) throws -> SyncMergePreview (or equivalent documented signature). Append chosen payload with parents covering all current heads, then archive duplicate-name losers as append-only revisions. Recompute semantic conflicts and existing note/count conflicts from resolved catalog.
- [ ] If resolving a content branch exposes new name collisions, return another preview requiring those choices rather than guessing. Note/count resolution remains unavailable until no content conflicts.
- [ ] Existing resolve(preview, choices:[String:SyncChoice],...) refuses unresolved content. All current tests for notes/manual counts and unseen wrong answers remain meaningful for schema 3.
- [ ] validateCommit compares all current events AND revisions to expected baseline, requires every current immutable record in proposed unchanged, and checks schema/limits. Caller additionally validates full catalog/references with codec.
- [ ] Bump packet compatibility version (document exact value in report) or add required explicit content-schema capability, keeping SHA256 built-in fingerprint independent of personal data. Existing encryption and confirmation state-machine semantics unchanged.
- [ ] Register/run locally possible checks, self-review and report UI-facing signatures and count meanings.

Important: old question-history lookups use all question revisions in merged catalog, not only active questions. No Dictionary(uniqueKeysWithValues:) on unconstrained word names.

## Task 3: Atomic runtime integration and personal-content UI

Files:
- Modify Words800App/DataManager.swift, WordLibraryView.swift, PracticeView.swift, AdaptiveLayout.swift as necessary.
- Modify Words800App/ProfileView.swift, NearbySyncModel.swift, NearbySyncView.swift, ContentView.swift, ErrorWordsView.swift where catalog/filter integrations require it.
- Create Words800App/PersonalContentViews.swift; split reusable forms and management views into focused files if necessary.
- Register new files in Words800App.xcodeproj/project.pbxproj and any test dependencies in tools/verify_macos.sh.
- Update README.md with feature usage, v3 backup/upgrade notes, and truthful v2.3.0 changelog. Do not create/change tags.
- Add focused native tests for extracted transaction/draft/filter helpers only where behavior can genuinely be tested outside an app.

Consumes: Tasks 1-2 interfaces and reports.
Produces: working user flows, unified persistence/sync, no placeholders or invisible feature implementations.

Steps:
- [ ] Add tests FIRST for any new pure transaction/filter helper and preserve existing native coverage. Drafts can be real value models, not duplicated test-only app logic.
- [ ] Keep builtInWords and builtInQuestions separate/private. Published all words and all question revisions support histories; maintain active catalog separately for new practice. DataManager loads store/codec, rebuilds learning/search once, and never silently continues writes after failed initial load.
- [ ] Add atomic savePersonalWord(content:wordID:expectedHeads:notes:) and savePersonalQuestion(content:entryID:expectedHeads:) APIs plus archive/restore. Validate content, active-name duplicates, stable head expectation, snapshot limits and graph before disk. Append word revision and optional existing-format note event in ONE proposed snapshot.
- [ ] Do not mutate published catalog or dismiss forms until store.save succeeds. On failure retain snapshot/draft and show concrete error. Once saved, rebuild and refresh reminders; preserve existing singleton learning APIs and old UserDefaults migration.
- [ ] Initial upgrade uses SnapshotStore v2 migration; keep old v2 files untouched. backup/import/export/nearby all carry same v3 snapshot; validatedSnapshot uses original built-in arrays and complete incoming catalog.
- [ ] Add word-library plus toolbar action and 全部 / 我的添加 filter; separate personal archive browsing from existing 原资料删除词 switch. Successful add selects the new word. Matching normalized existing words are shown with an Open existing action to add notes/questions.
- [ ] Word editor contains required word/meaning, optional pinyin/category/example/keyPoints/note, explicit length help; cancel with changes confirms discard. Show save failure inline/alert and keep text. Own sheet at stable parent across compact/wide layout; iPad max-width form uses system colors.
- [ ] Custom word details show 手动添加, no fabricated PDF section; notes retain current above-learning placement. Add edit/archive/restore for personal only, and 给这个词添加题目 for both built-in and personal. Show no related questions if absent, offer adding not auto-generation.
- [ ] Practice adds 我的题目 management and 添加题目; personal question list has active/archived filter, complete preview, edit/archive/restore. Practice kind uses QuestionType.personal and total counts only active versions.
- [ ] Question editor has stem, four option fields, unselected correct answer, explanation/source, searchable multi-select active word IDs. Support saving a new word inside selection without discarding the question draft. Save validates all required fields, no duplicate options/links.
- [ ] Keep question/word editor drafts stable across rotations; avoid placing modal .sheet only under alternate iPad layout branches. Manage stale heads after sync with a clear reopen/review error instead of overwriting remote edits.
- [ ] Route all personal question relationship displays and practice filtering/scoring to UUID helper. New practice excludes archived questions and filters by active related words; history retains original versions. Frozen PracticeSession questions plus version-ID submit keep in-flight sessions unchanged.
- [ ] Add content conflict stage and counts to BOTH file import and nearby previews. Show competing full payloads/state, resolve content first, refresh preview until no content conflicts, then old notes/error choices. Both sender and receiver see content differences even with zero learning events.
- [ ] Any local content change invalidates old pending sync proposals through full snapshot baseline. Receiving approval must retain all local immutable history; outgoing proposal can contain new resolution revisions.
- [ ] Exclude personal archived words in search defaults, daily cards, new/due/weak word picks and reminders. History remains navigable. Built-in categories and custom category fallback work; source labels never invent page numbers.
- [ ] Update README with word/question entry paths, required fields, archive/restore, immutable historical scoring, both devices upgrade before sync, v2 backup import and v3 exports.
- [ ] Run Python suite, project structural validation, full Swift parser checks (if installed), git diff --check. Native command is documented but not available locally; no claim IPA built.
- [ ] Self-review every UI entry -> atomic save -> after relaunch -> merge -> history path, report remaining real-device validation.

## Final verification and handoff

- [ ] Controller runs current Python tests and project/Swift parser checks, reviews exact dirty paths, confirms only requested local changes and unchanged bundle/build identity.
- [ ] Broad independent review uses approved spec plus complete working-tree diff and deferred findings; one scoped fix wave if needed.
- [ ] Leave changes uncommitted for GitHub Desktop. Report user entry paths and a short device checklist: add/edit/answer/history, archive, rotate iPad, synchronize.
- [ ] Clearly distinguish local passing checks from unexecuted GitHub native tests/IPA build and two-device validation.
