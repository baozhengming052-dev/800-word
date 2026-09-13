import Foundation

@main struct SnapshotStoreTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-store-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let t = 1_700_000_000_000.0
        let validate: (Data) throws -> StudySnapshot = { try SnapshotCodec.decode(data: $0, builtInWords: [], builtInQuestions: [], now: t) }
        func expect(_ condition: @autoclosure () throws -> Bool, _ message: String = "Store contract failed") rethrows {
            let result = try condition()
            assert(result, message)
        }
        let store = SnapshotStore(directory: directory, validate: validate)
        try expect(try store.load() == nil)
        let legacyURL = directory.appendingPathComponent("study-v2.json")
        let primaryURL = directory.appendingPathComponent("study-v3.json")
        let previousURL = directory.appendingPathComponent("study-v3.previous.json")
        let legacy = Data("{\"schemaVersion\":2,\"events\":[]}".utf8)
        try legacy.write(to: legacyURL)
        let migrated = try store.load()!
        assert(migrated.schemaVersion == 3)
        try expect(try Data(contentsOf: legacyURL) == legacy, "Migration never modifies v2 evidence")
        assert(FileManager.default.fileExists(atPath: primaryURL.path), "Migration persists v3")
        let word = PersonalRevision(entryID: UUID(), timestamp: t, word: PersonalWordContent(word: "持久词", meaning: "意义"))
        let first = StudySnapshot(revisions: [word])
        try store.save(first)
        try expect(try store.load()?.revisions == [word])
        let edited = PersonalRevision(entryID: word.entryID, parents: [word.id], timestamp: t, word: PersonalWordContent(word: "改名", meaning: "意义"))
        let second = StudySnapshot(revisions: [word, edited])
        try store.save(second)
        try expect(try store.load()?.revisions == [word, edited])
        let beforeInvalidSave = try Data(contentsOf: primaryURL)
        do { try store.save(StudySnapshot(revisions: [word, word])); fatalError("Expected validation failure") } catch { }
        try expect(try Data(contentsOf: primaryURL) == beforeInvalidSave, "Invalid save leaves persisted state untouched")
        let corrupt = Data("damaged v3".utf8)
        try corrupt.write(to: primaryURL)
        try expect(try store.load()?.revisions == [word], "Recover only previous valid v3")
        assert(store.recoveryMessage != nil)
        try expect(try Data(contentsOf: primaryURL) == corrupt, "Recovery retains original damaged primary")
        try store.save(first)
        let evidence = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("study-v3.corrupt-") }
        assert(evidence.count == 1)
        try expect(try Data(contentsOf: evidence[0]) == corrupt, "Repair saves damaged evidence before replacing primary")
        try corrupt.write(to: primaryURL)
        try corrupt.write(to: previousURL)
        do { _ = try store.load(); fatalError("Must not roll back to v2 when both v3 files are damaged") } catch { }
        // An actual filesystem failure must leave the caller's snapshot unchanged.
        let blocked = directory.appendingPathComponent("blocked")
        try Data("file, not directory".utf8).write(to: blocked)
        let failedStore = SnapshotStore(directory: blocked, validate: validate)
        var inMemory = first
        do { try failedStore.save(second); inMemory = second; fatalError("Expected write failure") } catch { }
        assert(inMemory.revisions == [word])
        try expect(try Data(contentsOf: legacyURL) == legacy)

        // A future payload need not contain any current-model fields. Detect its header first.
        let future = Data("{\"schemaVersion\":4,\"futureDirectory\":{\"onlyCopy\":true}}".utf8)
        let validV3 = try JSONEncoder().encode(first)
        func contents(_ location: URL) throws -> [String: Data] {
            var result: [String: Data] = [:]
            for file in try FileManager.default.contentsOfDirectory(at: location, includingPropertiesForKeys: nil) {
                result[file.lastPathComponent] = try Data(contentsOf: file)
            }
            return result
        }
        func rejectsFuture(_ action: () throws -> Void) {
            do { try action(); fatalError("Unsupported schema must not recover or save") }
            catch SnapshotStoreError.unsupportedSchema(let version) { assert(version == 4) }
            catch { fatalError("Expected explicit unsupported-schema error, got \(error)") }
        }
        func scenario(_ name: String, _ payloads: [String: Data]) throws -> (URL, SnapshotStore) {
            let location = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
            for (filename, bytes) in payloads { try bytes.write(to: location.appendingPathComponent(filename)) }
            return (location, SnapshotStore(directory: location, validate: validate))
        }
        let (futurePrimaryDirectory, futurePrimaryStore) = try scenario("future-primary", [
            "study-v3.json": future, "study-v3.previous.json": validV3, "study-v2.json": legacy
        ])
        let beforeFuturePrimary = try contents(futurePrimaryDirectory)
        rejectsFuture { _ = try futurePrimaryStore.load() }
        rejectsFuture { try futurePrimaryStore.save(first) }
        try expect(try contents(futurePrimaryDirectory) == beforeFuturePrimary,
            "Future primary and previous bytes/file set remain unchanged, including no corrupt-evidence copies")
        assert(futurePrimaryStore.recoveryMessage == nil)

        let (futurePreviousDirectory, futurePreviousStore) = try scenario("future-previous", [
            "study-v3.json": validV3, "study-v3.previous.json": future
        ])
        let beforeFuturePrevious = try contents(futurePreviousDirectory)
        rejectsFuture { try futurePreviousStore.save(second) }
        try expect(try contents(futurePreviousDirectory) == beforeFuturePrevious,
            "Saving cannot replace a future previous file with the current primary")
        let (onlyFutureBackupDirectory, onlyFutureBackupStore) = try scenario("only-future-backup", [
            "study-v3.previous.json": future
        ])
        let beforeOnlyFutureBackup = try contents(onlyFutureBackupDirectory)
        rejectsFuture { _ = try onlyFutureBackupStore.load() }
        rejectsFuture { try onlyFutureBackupStore.save(first) }
        try expect(try contents(onlyFutureBackupDirectory) == beforeOnlyFutureBackup,
            "An absent primary does not permit writing past a future backup")

        let (recoverFutureDirectory, recoverFutureStore) = try scenario("recover-future-previous", [
            "study-v3.json": corrupt, "study-v3.previous.json": future, "study-v2.json": legacy
        ])
        let beforeRecoverFuture = try contents(recoverFutureDirectory)
        rejectsFuture { _ = try recoverFutureStore.load() }
        rejectsFuture { try recoverFutureStore.save(first) }
        try expect(try contents(recoverFutureDirectory) == beforeRecoverFuture,
            "Recovery cannot skip a future previous file or change corrupt primary evidence")

        let (futureLegacyDirectory, futureLegacyStore) = try scenario("future-legacy", [
            "study-v2.json": future, "study-v2.previous.json": legacy
        ])
        let beforeFutureLegacy = try contents(futureLegacyDirectory)
        rejectsFuture { _ = try futureLegacyStore.load() }
        try expect(try contents(futureLegacyDirectory) == beforeFutureLegacy, "Future legacy primary blocks migration")
        let (futureLegacyPreviousDirectory, futureLegacyPreviousStore) = try scenario("future-legacy-previous", [
            "study-v2.json": corrupt, "study-v2.previous.json": future
        ])
        let beforeFutureLegacyPrevious = try contents(futureLegacyPreviousDirectory)
        rejectsFuture { _ = try futureLegacyPreviousStore.load() }
        try expect(try contents(futureLegacyPreviousDirectory) == beforeFutureLegacyPrevious,
            "A traversed future legacy backup rejects without creating v3 files")

        let malformedV3 = Data("{\"schemaVersion\":3,\"events\":\"damaged\",\"revisions\":[]}".utf8)
        let (knownMalformedDirectory, knownMalformedStore) = try scenario("known-malformed", [
            "study-v3.json": malformedV3, "study-v3.previous.json": validV3
        ])
        try expect(try knownMalformedStore.load()?.revisions == [word], "Known-v3 payload corruption still recovers")
        try expect(try Data(contentsOf: knownMalformedDirectory.appendingPathComponent("study-v3.json")) == malformedV3)
        try knownMalformedStore.save(first)
        try expect(try knownMalformedStore.load()?.revisions == [word], "Known-v3 recovery can still persist repaired state")
        print("PASS: migration, atomic saves, known-v3 recovery, future-schema protection and failed writes")
    }
}
