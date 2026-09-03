# 句子音檔不放進 `word_media`

聽句題（[ADR-0014](0014-listening-changes-the-rating-preconditions.md)）要為每一句例句預生成
音檔。那些音檔**不進 `word_media`**，而是進一張新表 `word_example_media`，唯一鍵
`(example_id, locale)`。

`word_media` 對音檔有這道唯一索引，一個字每個 locale 只能有一列：

```sql
CREATE UNIQUE INDEX word_media_audio_locale_uniq
  ON word_media(word_id, kind, locale) WHERE kind = 'audio'
```

一個字有兩句 ja-JP 例句就撞上。而就算把索引放寬，`lib/data.ts` 是這樣讀音檔的：

```sql
(SELECT jsonb_object_agg(m.locale, m.url)
 FROM word_media m
 WHERE m.word_id = w.id AND m.kind = 'audio' AND m.locale IS NOT NULL) AS audio_by_locale
```

**`jsonb_object_agg` 碰到重複的 key 不會報錯，會留最後一筆。** 句子音檔一旦進了
`word_media`，`audioUrls['ja-JP']` 就有機會變成某一句例句的錄音——單字的發音鈕會唸出一整句
話，而且沒有任何錯誤、沒有任何測試會紅。

新表的形狀不是發明出來的，這個 schema 已經有「一句例句、每個語言一列」了：

```sql
CREATE TABLE word_example_translations (
   example_id  BIGINT NOT NULL REFERENCES word_examples(id) ON DELETE CASCADE,
   language    TEXT NOT NULL,
   translation TEXT NOT NULL,
   PRIMARY KEY (example_id, language)
)
```

## Considered Options

**`word_media` 加一個 `example_id` 欄位**，改唯一索引，並且把上面那個子查詢補上
`AND m.example_id IS NULL` — 被拒。`word_media` 從名字到每一個索引都是以 `word_id` 為主鍵
概念的；加一個 `example_id` 之後，**每一個還不知道它存在的查詢都預設變成錯的**，而
`data.ts` 那句已經是其中一個、而且它錯得無聲。這是「同一條規則寫三四份、漏一份」那個形狀，
只是這次漏的那一份會讓單字發音唸出例句。

**`word_examples` 加一個 `audio_by_locale` JSONB 欄位** — 被拒。`scripts/generate-audio.ts`
的冪等性建立在 per-row UPSERT 上（「一個 (word_id, locale) 已經有列就跳過，除非 `--refresh`」），
JSONB 欄位做不到；重跑補缺會變成讀出來、合併、寫回去，而那條路上有 lost update。

`(example_id, locale)` 這個鍵對日文仍然成立，但要知道**文字不在同一張表**：
`word_examples.sentence` 存的是英文句（`words-db.ts` 的 INSERT 寫的是 `e.en`），日文與中文在
`word_example_translations`。所以 `example_id = X, locale = 'ja-JP'` 那一列的音檔，唸的是 X 的
**ja 翻譯**，不是 `X.sentence`。

## Consequences

`generate-audio.ts` 現在有兩種 job：單字的（`word_media`）與例句的（`word_example_media`）。
`buildAudioJobs(words, jaTerms)` 目前的 `AudioJob` 是 `{ wordId, locale, text }`，例句那一種
的 key 是 `example_id`，所以兩者不共用同一個 `AudioJob` 型別。

新表要跟 `word_media` 一樣 `ENABLE ROW LEVEL SECURITY` 並開公開讀取（`word_media_public_read`
的同一形狀）——例句音檔跟單字音檔一樣是公開內容，不是使用者資料。

要錄的是 **952 列**（476 個字 × 2），因為 `word_examples` 現在只剩 published 的字：2026-09-03
刪掉了 4 個 `archived` 的字留下的 6 列孤兒例句。錄音腳本仍應自己帶
`AND w.status = 'published'`：`applyMainWordExamplePairs` 那道每次部署都跑的守衛只看 published，
封存的字留下的孤兒例句在它射程之外。字元數 en 57,006 ＋ ja 24,402；en 比照
單字做 en-US ＋ en-GB 的話總計約 138K，在 Chirp 3 HD 每月 1M 的免費額度之內。
