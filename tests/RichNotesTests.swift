import Foundation

@main struct RichNotesTests {
    static func main() throws {
        let library = try JSONDecoder().decode(Library.self,
            from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let word = library.words[0]
        let other = library.words[1]
        let stamp = 1_700_000_000_000.0
        func check(_ snapshot: StudySnapshot) throws {
            _ = try SnapshotCodec.validate(snapshot: snapshot,
                builtInWords: library.words, builtInQuestions: library.questions)
        }
        func rejects(_ title: String, _ action: () throws -> Void) {
            do { try action(); fatalError(title) } catch { }
        }
        let legacy = RichNote.decode("旧版纯文字笔记")!
        assert(legacy.blocks.count == 1 && legacy.summary == "旧版纯文字笔记")
        let legacyRoundTrip = try legacy.encode()
        assert(legacyRoundTrip == "旧版纯文字笔记")

        // The core validator checks an immutable JPEG event and same-word references.
        let jpegBytes: [UInt8] = [0xFF, 0xD8, 0xFF] + Array(repeating: 0, count: 100) + [0xFF, 0xD9]
        let jpeg = Data(jpegBytes)
        let imageA = StudyEvent(wordID: word.id, kind: "noteImage", value: jpeg.base64EncodedString(), timestamp: stamp)
        let richA = try RichNote(blocks: [.paragraph("第一段"), .image(imageA.id), .paragraph("图片下方")]).encode()
        let noteA = StudyEvent(wordID: word.id, kind: "note", value: richA, timestamp: stamp + 1)
        let local = StudySnapshot(events: [imageA, noteA])
        try check(local)
        assert(RichNote.decode(noteA.value)?.blocks[1].imageID == imageA.id)
        let restored = try JSONDecoder().decode(StudySnapshot.self, from: JSONEncoder().encode(local))
        try check(restored)
        let largerJPEG = Data([UInt8(0xFF), 0xD8, 0xFF] + Array(repeating: 0, count: 1_000_000) + [0xFF, 0xD9])
        try check(StudySnapshot(events: [StudyEvent(wordID: word.id, kind: "noteImage",
            value: largerJPEG.base64EncodedString(), timestamp: stamp)]))
        let oversizedJPEG = Data([UInt8(0xFF), 0xD8, 0xFF] + Array(repeating: 0, count: NoteImageLimits.maximumBytes) + [0xFF, 0xD9])
        rejects("An image above 5 MB must reject backup") {
            try check(StudySnapshot(events: [StudyEvent(wordID: word.id, kind: "noteImage",
                value: oversizedJPEG.base64EncodedString(), timestamp: stamp)]))
        }
        rejects("Missing image must reject backup") { try check(StudySnapshot(events: [noteA])) }
        let foreign = StudyEvent(id: imageA.id, wordID: other.id, kind: "noteImage",
            value: jpeg.base64EncodedString(), timestamp: stamp)
        rejects("An image from a different word must reject backup") {
            try check(StudySnapshot(events: [foreign, noteA]))
        }

        let imageB = StudyEvent(wordID: word.id, kind: "noteImage", value: jpeg.base64EncodedString(), timestamp: stamp + 2)
        let richB = try RichNote(blocks: [.paragraph("另一段"), .image(imageB.id)]).encode()
        let noteB = StudyEvent(wordID: word.id, kind: "note", value: richB, timestamp: stamp + 3)
        let preview = try SyncMergeEngine.preview(local: local,
            incoming: StudySnapshot(events: [imageB, noteB]), words: library.words, questions: library.questions)
        assert(preview.conflicts.count == 1 && preview.conflicts[0].kind == .note)
        let merged = try SyncMergeEngine.resolve(preview,
            choices: [preview.conflicts[0].id: .combined], now: stamp + 10)
        try check(merged)
        let state = LearningEngine.reduce(words: library.words, questions: library.questions,
            events: merged.events).records[word.id]!
        let images = RichNote.decode(state.personalNotes)!.blocks.compactMap(\.imageID)
        assert(images == [imageA.id, imageB.id], "Conflict resolution must preserve both photos")
        print("PASS: legacy text, rich note backup references, and image-preserving sync merge")
    }
}
