import SwiftUI

/// 动作选择：按肌群分组（胸/背/腿/肩/臂/核心/有氧）
public struct ExercisePickerView: View {

    public struct Pick: Identifiable {
        public var id: String
        public var name: String
        public var muscle: String

        public init(id: String, name: String, muscle: String) {
            self.id = id
            self.name = name
            self.muscle = muscle
        }
    }

    let onPick: (Pick) -> Void

    #if os(iOS)
    @State private var search = ""
    #endif

    public init(onPick: @escaping (Pick) -> Void) {
        self.onPick = onPick
    }

    private var groups: [(muscle: String, exercises: [(id: String, zh: String, en: String)])] {
        let base = ExerciseLibrary.groupedSeeds()
        #if os(iOS)
        guard !search.isEmpty else { return base }
        return base.compactMap { g in
            let hits = g.exercises.filter { $0.zh.contains(search) || $0.en.localizedCaseInsensitiveContains(search) }
            return hits.isEmpty ? nil : (g.muscle, hits)
        }
        #else
        return base
        #endif
    }

    public var body: some View {
        List {
            ForEach(groups, id: \.muscle) { group in
                Section {
                    ForEach(group.exercises, id: \.id) { ex in
                        Button {
                            onPick(Pick(id: ex.id, name: ex.zh, muscle: group.muscle))
                        } label: {
                            Text(ex.zh)
                        }
                    }
                } header: {
                    Text(group.muscle)
                }
            }
        }
        #if os(iOS)
        .searchable(text: $search, prompt: "搜索动作")
        #endif
        .themedSurface()
        .navigationTitle("选择动作")
    }
}
