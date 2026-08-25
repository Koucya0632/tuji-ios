# 自製圖鑑的補充花費，每個項目都有一個有限的上限

補充（enrichment，`enrichAtlasItem`）替一個自製圖鑑項目生出釋義、助記、詞源與各語言
gloss。它一次是三到四次付費模型呼叫，不是一次：`enrichWord`、日文讀音（僅 JA 且缺讀音
時）、`generateJapaneseAtlasDefinition`、`generateAtlasGlossPack`。

**每個項目在同一個 `ATLAS_ENRICH_VERSION` 下，最多補充 `ATLAS_ENRICH_MAX_ATTEMPTS`
次。** 用完之後 `backfill_status` 轉為 `skipped`，`skipped` 永不觸發 AI。這個上限是**有限
次數**，不是速率——項目數本身已經被圖鑑格數（免費 3、Pro 300）綁住，所以兩者相乘就是一個
使用者在補充上的花費天花板。

「該不該花這筆錢」只有一個答案來源：`shouldEnrichAtlasItem`。在此之前它被寫了三份，其中
兩份會花錢：

- `GET /api/atlas/items/:id/detail` — `backfill_status !== 'filled' || needsEnrichRefresh()`
- `POST /api/atlas/items/:id/enrich` — 無條件
- `GET /api/users/custom-words` — `=== 'filled' && !needsEnrichRefresh()`，只決定嵌不嵌資料

失敗會寫 `backfill_status = 'failed'`，而 `'failed' !== 'filled'` 恆真。一個穩定失敗的項目
——模型踩到某個 lemma、schema 驗不過——使用者每點開一次詳情就重跑一次完整的付費流程，
沒有盡頭。根因不是缺 rate limit，是 `failed` 同時背著「這次壞了，再試」和「這個一直壞」
兩個意思，重試決策沒有記憶。`skipped` 這個狀態早就宣告在 schema 的 CHECK 和 TS 型別裡，
從來沒有任何一行寫入它。

升級 `ATLAS_ENRICH_VERSION` 會讓 `skipped` 復活並把計數歸零，因為 `skipped` 的意思是
「用**這一版配方**我們試不出來」。配方換了就該再試一次，否則每次踩到 bug 的那批項目會
永久沉底，而且沒有任何地方會告訴你沉了多少。

## Considered Options

**GET 不再花錢，補充一律走 POST** — 被拒。付費副作用掛在最容易被打的動詞上確實是這個
漏洞的結構原因，讀取就該只是讀取。但修法要改 iOS 合約、發新版，而舊版 App 會永遠看到
未補充的項目。**成本導向的修改不該拖著客戶端合約一起改**，而且嘗試預算已經讓 GET 的花費
收斂到有限值，乾淨的分層在這裡買不到額外的安全。

**時間退避（failed 後 N 小時內不重試）** — 被拒。不用加狀態，但它的天花板是「每 N 小時
一次」：項目活得越久花得越多，永遠不收斂。我們要的是一個會結束的數字。

**補充吃每月 AI 配額（30／500）** — 被拒。最嚴格，但正常拍一張照要吃兩次配額（辨識 +
補充），等於把免費使用者的實際可拍次數從 30 砍到 15。那是產品決策，不該用成本的理由去改
它。配額賣的是「你能拍幾張」，不是「我們內部跑了幾次模型」。

**`failed` 直接就是終局，不加計數** — 被拒。一行判斷式就能擋住，但一次 OpenAI 的 500
或網路抖動就永久毀掉一個使用者剛拍的項目，而且沒有任何機制救得回來。這個產品沒有 admin
重試介面。

## Consequences

`skipped` 的項目退化成「只顯示名字跟圖」。這是既有且已被接受的狀態——JA 自製卡在 reading
為 null 時本來就長這樣。它不是新的壞掉形狀。

abuse backstop（`checkAtlasAiBackstops`，每 IP 每分鐘 12 次、全域每日 5000 次）現在也蓋到
補充，但**只在真的要花錢的那條分支消耗**。掛在 route 入口會讓正常瀏覽被自己的節流擋掉：
使用者快速點開十幾個項目是合理行為，而那些請求絕大多數根本不花錢。

計數跟它累積時的版本一起存（`backfill_attempts` + `backfill_attempts_version`），所以
「本版已試幾次」是從資料列算出來的，不是誰記得去重設的。第一版設計把復活邏輯放在失敗寫入
端，那是錯的：失敗**不會**蓋 `enrichVersion`（只有成功的 `updateAtlasItemEnrichment` 會），
所以一個在現行版本下持續失敗的項目，`needsEnrichRefresh` 永遠為真——只要讓「版本落後」
短路預算檢查，計數器就永遠不會生效，整個修法等於沒做。存成對之後，`skipped` 在判斷式裡
連分支都不需要：一個項目會是 `skipped`，恰好就是它在該版本下把預算用完了。少一個真相來源。

規則住在新的 `lib/atlas/enrich-policy.ts`，不在 `enrich.ts`。後者 import `server-only`
和整個 AI SDK，而問「這筆該不該花錢」的是 route handler、DB 寫入端跟測試——沒有一個該為了
問這句話把模型客戶端拖進來。測試根本 import 不了原本的模組，這件事本身就是分層錯了的訊號。

`ATLAS_ENRICH_VERSION` 的註解原本寫著「the stamp is unconditional so a failed generation
can't loop」。那句話正是這個 bug 藏了這麼久的原因：拋例外的失敗根本不會蓋戳記。註解已改。

`ATLAS_ENRICH_VERSION` 因此成為唯一的重生成槓桿，而它是全域的：bump 一次，所有落後版本
的項目都會在下次被讀到時重跑。這是刻意的——這個產品沒有 admin 端的單項重試，加一個是為了
還沒發生的問題先付錢。
