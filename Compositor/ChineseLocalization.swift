import Foundation

/// Translate display text only. Serialized model values and shortcut identities remain English.
nonisolated enum ChineseLocalization {
    static let strings: [String: String] = {
        guard let url = Bundle.main.url(forResource: "ChineseLocalization", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return result
    }()
    static func translate(_ value: String) -> String {
        if let translated = strings[value] { return translated }
        if value.hasSuffix("…") { return translate(String(value.dropLast())) + "…" }
        if value.hasSuffix("...") { return translate(String(value.dropLast(3))) + "…" }
        for separator in [" › ", " · "] where value.contains(separator) {
            return value.components(separatedBy: separator).map(translate).joined(separator: separator)
        }
        if let range = value.range(of: " (") {
            let head = String(value[..<range.lowerBound])
            if let translated = strings[head] { return translated + value[range.lowerBound...] }
        }
        for (english, chinese) in [("Undo ", "撤销 "), ("Redo ", "重做 "), ("Last Filter: ", "上次使用的滤镜："),
                                    ("Delete ", "删除 "), ("Hide ", "隐藏 "), ("Show ", "显示 "),
                                    ("Add ", "添加 "), ("Edit ", "编辑 "), ("Copy ", "复制 "),
                                    ("Remove ", "移除 "), ("Cancel ", "取消 "), ("Export ", "导出 "),
                                    ("Develop “", "RAW 显影：“"), ("Align ", "对齐：")] {
            if value.hasPrefix(english) { return chinese + translate(String(value.dropFirst(english.count))) }
        }
        if value.hasSuffix(" Selection") { return translate(String(value.dropLast(10))) + "选区" }
        return value
    }
}
nonisolated func zh(_ value: String) -> String { ChineseLocalization.translate(value) }
