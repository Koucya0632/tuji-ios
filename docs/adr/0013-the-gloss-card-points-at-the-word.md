# 詞塊卡片指著那個詞，而排版還是 SwiftUI 的

點例句裡的一個詞塊，升起的卡片浮在那個詞旁邊、尖角對準它，那個詞同時在句子裡上一道黃色
螢光筆。位置是**量出來的**：被選中的詞塊帶一個 `TextAttribute`，一個 `TextRenderer` 從
SwiftUI 已經算好的 `Text.Layout` 裡把那個 run 的 `typographicBounds` 讀出來。

[ADR-0009](0009-example-sentence-annotation.md) 把整句交給 SwiftUI 的文字引擎——一個
`AttributedString`，每個可點的詞塊一個 link——換到的是正確斷行、Dynamic Type、日文禁則與
文字選取，而付出的代價寫在 `GlossCard.swift` 的檔頭上：**link 不回報它落在哪裡**，所以卡片
只能釘在螢幕底部。使用者點一個詞，答案出現在螢幕另一頭，而句子裡沒有任何東西記得剛剛點的是
哪一個。一句話裡有五、六個可點的詞時，這件事最明顯。

`Text.Layout`（iOS 18）把那個代價買回來，**而且不必把排版拿回來**。上面那四件事一件都沒有
換掉——這正是選它而不選其他做法的理由。

## 為什麼不逐詞排一列 view

最直覺的做法是把句子排成一排 `Text`，每個詞塊一個 view，位置就自己知道了。三個理由否掉它：

1. **它已經以 bug 的形式上線過一次。** 自訂 `Layout` 放在 `Spacer(minLength:)` 旁邊（例句卡
   就是這個位置）只會協商到一半的可用寬度。solver 的測試全綠，只有截圖看得出來，而
   `InteractiveSentenceText` 的檔頭就是為了記住這件事才寫的。
2. **斷行要自己做。** 英文的連字、日文的禁則、以及「`look forward to` 不能被拆開」這件事，
   一旦離開文字引擎就全都變成自己的事。
3. **文字選取沒了。**

## 為什麼不用 `UITextView`

TextKit 給得出字形矩形，但這個 App 的字級是 `TujiTypeface` 手工套 `UIFontMetrics` 再用
`UIFontDescriptor.cascadeList` 接上 CJK 字體的（[ADR-0003](0003-cjk-rounded-typeface.md)），
換一個渲染器就要把那整套在 UIKit 這邊再蓋一次，而 `Font(UIFont)` 會靜默地把 Dynamic Type
關掉。為了一個矩形，賭上每一句例句的字體與縮放。

## 兩件在裝置上才知道的事

**自訂 `AttributedStringKey` 活不到 `Text.Layout`。** 在 `AttributedString` 的 run 上設一個
同時符合 `AttributedStringKey` 與 `TextAttribute` 的 key，型別檢查會過、畫面會正常，但 run
在 renderer 裡回來時**是沒有標記的**——量測永遠得到 nil，而 nil 剛好等於「退回底部卡片」，
所以它會安靜地表現得像功能沒做。活得下來的是 `Text` 自己的 `customAttribute`，所以被選中的
詞塊要單獨切成一個 `Text` 串接回去。切出來的那一塊**保留它在整句裡的索引**：link 帶的是
索引，用切片重編號會讓它後面每一個詞都開錯的詞條。

**renderer 只在該句握有選取時掛上去。** 那一刻遮罩已經蓋住句子，link 本來就點不到，所以
自訂 renderer 對命中測試做了什麼都無所謂；其餘每一次渲染，句子都還是它本來的那個 `Text`。

## Consequences

- **量不到錨點就退回底部卡片，而且不畫尖角。** 沒有量到、或上下都塞不下（大字級 × 小螢幕），
  卡片就回到螢幕底部——也就是這個功能上一個版本的樣子。跟「串不回原句就退回純文字」同一條
  規則：失敗模式是舊版本，不是一個指著錯的詞的尖角。
- **擺放的算術是純函式。** `GlossCalloutPlacement`（上方優先、塞不下翻到下方、尖角夾在卡片
  內、都塞不下回傳 nil）跟 `ReviewRevealLayout` 同一個形狀，因為同一個理由：一台裝置的一張
  截圖只證明其中一個答案。
- **本專案第一個 `Shape`。** 外框與尖角是同一條 `Path`，`tujiRule` 的 1px 邊才不會在接縫處
  斷掉。連帶地 `Space` 變成 `nonisolated`——`Shape.path(in:)` 不在主執行緒上，而這個專案預設
  MainActor 隔離（Debug 只給警告，TestFlight 的 `-O -wmo` 會擋下來）。
- **卡片不再是抽屜，所以沒有 grabber、也沒有下拉關閉。** 關閉是點遮罩與 VoiceOver 的 escape。
  「看完整詳情」從整條按鈕縮成一行動作列：要塞進一個詞上方的空隙，高度就是預算。
- **視覺仍然是紙與墨。** 方角、紙色底、1px `tujiRule`、**沒有陰影**；浮起來的感覺由既有的
  `tujiScrim` 負責。反白是 `tujiBrandPrimary` 淡化的螢光筆，而可點的點狀底線留著——反白不是
  唯一的訊號。
