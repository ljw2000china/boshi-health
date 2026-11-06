#if os(iOS)
import SwiftUI
import PhotosUI

/// 第三页：设置（外观 / 数据 / 关于）
struct SettingsView: View {

    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var hk: HKService

    @State private var pickerItem: PhotosPickerItem?
    @State private var busy = false
    @State private var message: String?
    @State private var pipeline: [DataPipeline.SleepPipelineRow] = []
    @State private var showPipeline = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    appearanceSection
                    dataSection
                    aboutSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
            .themedSurface()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PageTitleBar(text: "设置", theme: theme)
                }
            }
            .task { pipeline = await DataPipeline.shared.sleepPipelineReport(days: 7) }
        }
        .themeBackground()
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("外观")

            Text("背景")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(PulseDesign.labelSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                      spacing: 10) {
                ForEach(ThemeStore.BackgroundStyle.allCases) { style in
                    backgroundTile(style)
                }
            }

            Divider().opacity(0.4)

            // 照片壁纸
            PhotosPicker(selection: $pickerItem, matching: .images) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text(theme.hasWallpaper ? "更换手机照片作为壁纸" : "用手机照片作为壁纸")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.right").font(.size13)
                }
                .foregroundStyle(PulseDesign.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data),
                       let jpg = ui.jpegData(compressionQuality: 0.9) {
                        theme.saveWallpaper(jpg)
                        theme.background = .photo
                        message = "壁纸已更新（自适应铺满屏幕）"
                    }
                    pickerItem = nil
                }
            }

            if theme.hasWallpaper {
                Button(role: .destructive) {
                    theme.removeWallpaper()
                    message = "已删除壁纸"
                } label: {
                    Label("删除壁纸", systemImage: "trash")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }

            Divider().opacity(0.4)

            // 卡片透明度
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("卡片透明度")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(String(format: "%.0f%%", theme.cardOpacity * 100))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(PulseDesign.accent)
                }
                Slider(value: Binding(get: { theme.cardOpacity },
                                      set: { theme.cardOpacity = $0 }),
                       in: 0.02...0.6, step: 0.02)
                    .tint(PulseDesign.accent)
                Text("数值越小框越透明")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseDesign.labelTertiary)
            }

            // 标题字体
            VStack(alignment: .leading, spacing: 8) {
                Text("标题字体")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                HStack(spacing: 8) {
                    ForEach(ThemeStore.TitleFont.allCases) { f in
                        Button {
                            theme.titleFont = f
                        } label: {
                            Text(f.nameZh)
                                .font(.system(size: 13, weight: .semibold,
                                              design: f == .rounded ? .rounded
                                                    : (f == .serif ? .serif : .default)))
                                .foregroundStyle(theme.titleFont == f ? .white : .primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(theme.titleFont == f
                                                   ? AnyShapeStyle(PulseDesign.mainGradient)
                                                   : AnyShapeStyle(Color.secondary.opacity(theme.cardOpacity + 0.06)))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
        }
        .pulseCard(padding: 16)
    }

    private func backgroundTile(_ style: ThemeStore.BackgroundStyle) -> some View {
        let selected = theme.background == style
        return Button {
            theme.background = style
        } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: ThemeBackgroundView.colors(for: style),
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 46)
                    .overlay {
                        if style == .photo {
                            Image(systemName: "photo")
                                .font(.size15)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selected ? AnyShapeStyle(PulseDesign.mainGradient)
                                             : AnyShapeStyle(Color.clear), lineWidth: 2)
                    )
                Text(style.nameZh)
                    .font(.system(size: 11, weight: selected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(selected ? PulseDesign.accent : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 数据

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("数据")

            HStack {
                Label("健康授权", systemImage: "heart.text.square")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                Spacer()
                Text(authText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(hk.authState == .requested ? .green : .orange)
            }

            PulseSecondaryButton("请求健康权限 / 重新授权") {
                Task { await hk.requestAuthorizationIfNeeded() }
            }

            PulseProminentButton(busy ? "正在重拉 60 天…" : "修复睡眠：清缓存重拉 60 天",
                                 systemImage: "arrow.triangle.2.circlepath") {
                Task {
                    busy = true
                    await hk.requestAuthorizationIfNeeded()
                    await DataPipeline.shared.forceRebuild(days: 60)
                    pipeline = await DataPipeline.shared.sleepPipelineReport(days: 7)
                    showPipeline = true
                    busy = false
                    message = "已重拉完成，若仍为空请看下方管线"
                }
            }
            .disabled(busy)

            Button {
                Task {
                    pipeline = await DataPipeline.shared.sleepPipelineReport(days: 7)
                    showPipeline.toggle()
                }
            } label: {
                HStack {
                    Text("睡眠管线诊断（近 7 天）")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: showPipeline ? "chevron.up" : "chevron.down")
                        .font(.size12)
                }
                .foregroundStyle(PulseDesign.accent)
                .contentShape(Rectangle())
            }

            if showPipeline {
                VStack(spacing: 6) {
                    HStack {
                        Text("日期").frame(width: 74, alignment: .leading)
                        Text("睡眠样本").frame(width: 52, alignment: .trailing)
                        Text("分段").frame(width: 36, alignment: .trailing)
                        Text("L0").frame(width: 30, alignment: .trailing)
                        Text("窗口").frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(PulseDesign.labelTertiary)

                    ForEach(pipeline, id: \.dayKey) { r in
                        HStack {
                            Text(shortKey(r.dayKey)).frame(width: 74, alignment: .leading)
                            Text("\(r.rawSleepSamples)").frame(width: 52, alignment: .trailing)
                            Text("\(r.segments)").frame(width: 36, alignment: .trailing)
                            Text("\(r.l0Candidates)").frame(width: 30, alignment: .trailing)
                            Text(r.windowSource == "—" ? "无"
                                 : "\(r.windowSource) \(Int(r.windowMin))分")
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .foregroundStyle(r.windowSource == "—" ? .red : .secondary)
                        }
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                }
                .padding(.top, 4)
            }

            if let message {
                Text(message)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseDesign.labelSecondary)
            }

            Divider().opacity(0.4)

            NavigationLink {
                PulseLogView()
            } label: {
                HStack {
                    Label("同步日志（排查用）", systemImage: "doc.text.magnifyingglass")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.right").font(.size13)
                        .foregroundStyle(PulseDesign.labelTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            NavigationLink {
                DebugDataView()
            } label: {
                HStack {
                    Label("调试数据", systemImage: "wrench.and.screwdriver")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.right").font(.size13)
                        .foregroundStyle(PulseDesign.labelTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .pulseCard(padding: 16)
    }

    private var authText: String {
        switch hk.authState {
        case .unavailable:   return "不可用"
        case .notRequested:  return "未授权"
        case .requested:     return "已授权"
        case .failed:        return "失败"
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("关于")
            HStack {
                Text("薄士")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Text("个人版 · 仅本机数据")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(PulseDesign.labelSecondary)
            }
            Text("所有健康数据只保存在这台 iPhone 与本机数据库中，不上传任何服务器；训练组次通过蓝牙在手表与手机之间同步。")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(PulseDesign.labelSecondary)
                .lineSpacing(3)
        }
        .pulseCard(padding: 16)
    }

    private func sectionHeader(_ t: String) -> some View {
        PulseDesign.SectionLabel(t)
    }

    private func shortKey(_ key: String) -> String {
        // 2026-11-05 → 11/05
        let parts = key.split(separator: "-")
        guard parts.count == 3 else { return key }
        return "\(parts[1])/\(parts[2])"
    }
}

private extension Font {
    static let size12 = Font.system(size: 12, weight: .semibold)
    static let size13 = Font.system(size: 13, weight: .semibold)
    static let size15 = Font.system(size: 15, weight: .semibold)
}
#endif
