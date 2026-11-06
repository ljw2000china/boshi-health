import Foundation

/// 轻量文件日志：用于排查「健康数据一条都进不来」这类静默失败。
/// 写 Documents/pulse.log，超过 256KB 自动截断（只保留后半）。
public enum PulseLog {

    public static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pulse.log")
    }

    private static let queue = DispatchQueue(label: "pulse.log")

    public static func write(_ msg: String) {
        queue.async {
            let f = DateFormatter()
            f.dateFormat = "MM-dd HH:mm:ss"
            let line = "[\(f.string(from: Date()))] \(msg)\n"
            guard let data = line.data(using: .utf8) else { return }
            let fm = FileManager.default
            if let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
            if let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int, size > 256_000,
               let all = try? String(contentsOf: url, encoding: .utf8) {
                let tail = String(all.suffix(128_000))
                try? tail.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    public static func read() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? "（无日志）"
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
