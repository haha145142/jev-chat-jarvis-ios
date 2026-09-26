import SwiftUI

/// 知识库页：内置笔记查看与开关。笔记只存本机，分析时按标签命中对方消息。
struct NotesView: View {
    @EnvironmentObject private var store: ConfigStore
    @State private var notes: [JevNote] = []

    private func reload() { notes = JevNoteStore.loadNotes() }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(notes.filter { $0.alwaysOn }) { note in
                        row(note)
                    }
                } header: {
                    Text("常驻（每次分析都带上）")
                }
                Section {
                    ForEach(notes.filter { !$0.alwaysOn }) { note in
                        row(note)
                    }
                } header: {
                    Text("按需命中（标签或标题出现在对方消息里时自动带上）")
                } footer: {
                    Text("共 \(notes.count) 条笔记，只存在本机、不上传。命中规则与安卓版一致：最多 5 条、合计约 1500 字。")
                }
            }
            .navigationTitle("知识库")
            .onAppear { reload() }
        }
    }

    private func row(_ note: JevNote) -> some View {
        NavigationLink {
            NoteDetail(note: note) { reload() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: note.enabled ? "book.fill" : "book")
                    .foregroundStyle(note.enabled ? Color.green : Color.gray)
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title).font(.subheadline.weight(.medium))
                    if !note.tags.isEmpty {
                        Text(note.tags.joined(separator: "、"))
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

/// 笔记详情：正文 + 启用/常驻开关。
struct NoteDetail: View {
    @State var note: JevNote
    let onChanged: () -> Void

    var body: some View {
        List {
            Section("内容") {
                Text(note.content)
                    .font(.callout)
                    .padding(.vertical, 4)
            }
            if !note.tags.isEmpty {
                Section("命中标签") {
                    Text(note.tags.joined(separator: "、")).font(.footnote)
                }
            }
            Section {
                Toggle("启用", isOn: Binding(
                    get: { note.enabled },
                    set: { note.enabled = $0; JevNoteStore.update(note); onChanged() }))
                Toggle("常驻（每次分析都带上）", isOn: Binding(
                    get: { note.alwaysOn },
                    set: { note.alwaysOn = $0; JevNoteStore.update(note); onChanged() }))
            }
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
