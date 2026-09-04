// 版本號要能比大小，而字串比較會說 "1.1.10" 比 "1.1.9" 小 —— 那是錯的，
// 而且錯的方向剛好是「該提示的時候不提示」，安靜到沒人會發現。
//
// 只認純數字的點分段。任何一段不是數字（`1.2-beta`、空字串、`1..2`）就整個
// 判定為無法比較：這個型別唯一的用途是決定要不要打擾使用者，看不懂的時候
// 閉嘴才是對的預設，所以失敗是 `nil` 而不是一個猜出來的值。

import Foundation

struct AppVersion: Comparable {
    /// 已經拆成數字的每一段。`1.1` 是 `[1, 1]`，不會自己補成 `[1, 1, 0]`。
    let components: [Int]

    init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var parsed: [Int] = []
        for part in trimmed.split(separator: ".", omittingEmptySubsequences: false) {
            // `Int("+1")` 是 1，`Int("１")` 是 1。兩個都不是我們想放行的形狀。
            guard !part.isEmpty,
                  part.allSatisfy(\.isASCII),
                  part.allSatisfy(\.isNumber),
                  let number = Int(part)
            else { return nil }
            parsed.append(number)
        }
        self.components = parsed
    }

    /// `1.2` 和 `1.2.0` 是同一版：短的那邊補 0 再逐段比。
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = lhs.segment(at: index)
            let right = rhs.segment(at: index)
            if left != right { return left < right }
        }
        return false
    }

    /// 手寫的，不是合成的：合成版會說 `[1, 2]` 不等於 `[1, 2, 0]`。
    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    private func segment(at index: Int) -> Int {
        self.components.indices.contains(index) ? self.components[index] : 0
    }
}
