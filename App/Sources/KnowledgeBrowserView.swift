import SwiftUI

/// 内置知识库浏览：列出随包内置的「狗头军师」43 篇文献，点进去看全文。
/// 恋爱大师的阶段打法在 Shared/LoveCoach.swift（方法内建，不随文件展示）。
struct KnowledgeBrowserView: View {
    struct Doc: Identifiable {
        let id: String
        let rel: String
        let title: String
        let body: String
    }

    @State private var docs: [Doc] = []

    var body: some View {
        List {
            if docs.isEmpty {
                Text("没找到内置知识库：请确认安装的是终极融合版。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(docs) { d in
                NavigationLink {
                    ScrollView {
                        Text(d.body)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle(d.title)
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.title).font(.subheadline)
                        Text(d.rel).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("内置知识库")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func load() {
        guard let root = GoutouKnowledge.folderURL else { return }
        var out: [Doc] = []
        if let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let u as URL in en where u.pathExtension == "md" {
                guard let s = try? String(contentsOf: u, encoding: .utf8) else { continue }
                let rel = u.path.replacingOccurrences(of: root.path + "/", with: "")
                let title = firstTitle(in: s) ?? u.deletingPathExtension().lastPathComponent
                out.append(Doc(id: rel, rel: rel, title: title, body: s))
            }
        }
        docs = out.sorted { $0.rel < $1.rel }
    }

    private func firstTitle(in s: String) -> String? {
        s.split(separator: "\n", omittingEmptySubsequences: true)
            .first { $0.hasPrefix("#") }
            .map {
                String($0)
                    .replacingOccurrences(of: "#", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
    }
}
