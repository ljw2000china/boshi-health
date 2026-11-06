import SwiftUI

/// 同步日志查看（长文可选复制）
struct PulseLogView: View {

    @State private var text = ""
    @State private var showCopied = false

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 10.5, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .themedSurface()
        .navigationTitle("同步日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("刷新") { text = PulseLog.read() }
                    Button("复制全部") {
                        UIPasteboard.general.string = text
                        showCopied = true
                    }
                    Button("清空", role: .destructive) {
                        PulseLog.clear()
                        text = PulseLog.read()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { text = PulseLog.read() }
        .overlay(alignment: .bottom) {
            if showCopied {
                Text("已复制")
                    .font(.footnote)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        showCopied = false
                    }
            }
        }
    }
}
