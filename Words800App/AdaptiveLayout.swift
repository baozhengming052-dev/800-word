import Foundation

enum AdaptiveLayoutRules {
    static func usesTwoColumns(width: CGFloat, height: CGFloat, regularWidth: Bool) -> Bool {
        regularWidth && width >= 1000 && width > height
    }
}

#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

/// Gives plain/card buttons an immediate touch-down response without delaying their action.
struct ResponsivePressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

enum WordEditorKind { case notes, errors, source, personalWord, addQuestion }

struct WordEditorRequest: Identifiable {
    let id = UUID()
    let word: Word
    let kind: WordEditorKind
}

private struct PresentWordEditorKey: EnvironmentKey {
    static let defaultValue: ((WordEditorRequest) -> Void)? = nil
}

extension EnvironmentValues {
    var presentWordEditor: ((WordEditorRequest) -> Void)? {
        get { self[PresentWordEditorKey.self] }
        set { self[PresentWordEditorKey.self] = newValue }
    }
}

struct WordEditorSheet: View {
    let request: WordEditorRequest

    var body: some View {
        switch request.kind {
        case .notes: NotesEditorView(word: request.word)
        case .errors: ErrorCountEditor(word: request.word)
        case .source: SourcePDFView(page: request.word.occurrences.first?.page ?? 1)
        case .personalWord: PersonalWordEditor(wordID: request.word.id)
        case .addQuestion: PersonalQuestionEditor(relatedWordIDs: [request.word.id])
        }
    }
}

/// A stable master column keeps search, filters and list position during rotation.
struct AdaptiveWordBrowser<Sidebar: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let title: String
    let words: [Word]
    @Binding var selection: UUID?
    let sidebar: (Bool, Binding<Bool>) -> Sidebar
    @State private var compactDetailPresented = false
    @State private var editorRequest: WordEditorRequest?

    init(title: String, words: [Word], selection: Binding<UUID?>,
         @ViewBuilder sidebar: @escaping (Bool, Binding<Bool>) -> Sidebar) {
        self.title = title
        self.words = words
        self._selection = selection
        self.sidebar = sidebar
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = AdaptiveLayoutRules.usesTwoColumns(
                width: geometry.size.width, height: geometry.size.height,
                regularWidth: horizontalSizeClass == .regular)
            HStack(spacing: 0) {
                NavigationView {
                    sidebar(wide, $compactDetailPresented)
                        .navigationTitle(title)
                        .background(
                            NavigationLink(isActive: $compactDetailPresented) {
                                selectedDetail
                            } label: { EmptyView() }.hidden()
                        )
                }
                .navigationViewStyle(.stack)
                .frame(width: wide ? min(420, geometry.size.width * 0.34) : nil)
                if wide {
                    Divider()
                    NavigationView { selectedDetail }
                        .navigationViewStyle(.stack)
                        .id(selection)
                        .frame(maxWidth: .infinity)
                }
            }
            .onChange(of: wide) { isWide in
                compactDetailPresented = !isWide && selection != nil
            }
            .onChange(of: selection) { id in
                if !wide { compactDetailPresented = id != nil }
            }
            .onChange(of: words.map(\.id)) { ids in
                if let selected = selection, !ids.contains(selected) {
                    compactDetailPresented = false
                    selection = nil
                }
            }
        }
        // The sheet belongs to the browser, not the detail host replaced by rotation.
        .sheet(item: $editorRequest) { WordEditorSheet(request: $0) }
    }

    @ViewBuilder private var selectedDetail: some View {
        if let word = words.first(where: { $0.id == selection }) {
            WordDetailView(word: word).id(word.id)
                .environment(\.presentWordEditor, { request in editorRequest = request })
        } else {
            VStack(spacing: 16) {
                Image(systemName: "book.closed").font(.system(size: 42)).foregroundColor(AppStyle.accent)
                Text("选择一个词，展开学习").font(.title3.weight(.semibold))
                Text("在左侧查看词条，点选后阅读释义与个人笔记。")
                    .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        }
    }
}

struct AdaptiveWordLink: View {
    let word: Word
    let errorActivityDate: Date? = nil
    let isWide: Bool
    @Binding var selection: UUID?
    @Binding var compactDetailPresented: Bool

    var body: some View {
        Button {
            selection = word.id
            if !isWide { compactDetailPresented = true }
        } label: {
            HStack {
                WordRowView(word: word, errorActivityDate: errorActivityDate)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            }.contentShape(Rectangle())
        }
        .buttonStyle(ResponsivePressButtonStyle())
        .accessibilityAddTraits(isWide && selection == word.id ? .isSelected : [])
    }
}

/// AnyLayout preserves the identity of question and options on iOS 16 rotation.
struct AdaptivePracticeColumns<Content: View>: View {
    let wide: Bool
    let content: () -> Content

    init(wide: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.wide = wide
        self.content = content
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            let layout = wide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 32))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
            layout { content() }
        } else {
            VStack(alignment: .leading, spacing: 20) { content() }
        }
    }
}
#endif
