# Tuji Bug Report — 代码审查

> 基于 tuji-ios (main) + illustrated_book (89b3361) + tuji 三个仓库的全量源码审查。
> 审查日期：2026-06-21

---

## P0：阻断核心功能

### BUG-01: Apple 登录报错 "Provider not enabled"

- **严重程度**: P0
- **位置**: Supabase Dashboard 配置 / `AuthService.swift:signInWithApple()`
- **现象**: 用户点击 Apple 登录后报错 "Provider not enabled"
- **原因**: 这不是代码 bug。iOS 端代码完全正确（`signInWithIdToken` + `OpenIDConnectCredentials(provider: .apple, ...)` 写法标准）。问题在 **Supabase Dashboard → Authentication → Providers** 中 Apple 没有被启用。需要在 Supabase 后台配置 Apple OAuth Provider，填入 Service ID、Key ID、Team ID 等。
- **建议修复**: Supabase Dashboard → Authentication → Providers → Apple → Enable，填入 Apple Developer 提供的凭证。iOS 端零改动。

### BUG-02: 复习按钮点不了

- **严重程度**: P0
- **位置**: `TodayView.swift:reviewDisabled` (约行 198)
- **现象**: 首页的"復習"按钮灰色不可点击
- **原因**: 按钮使用了 `NavigationLink(value: NavRoute.studyLanding(mode: .review))` + `.disabled(self.reviewDisabled)`。`reviewDisabled` 逻辑：
  ```swift
  private var reviewDisabled: Bool {
      self.isGuest || (self.studyStats.stats?.due ?? 0) == 0
  }
  ```
  当 `studyStats.stats` 为 `nil`（网络错误、首次加载未完成、或 API 返回异常）时，`due` 默认为 0 → 按钮禁用。**此外，如果 stats 的缓存了旧数据（30 秒 TTL），新产生的 due 卡片不会立即反映。**
  
  但更可能的原因是：**用户是新账号，确实没有 due 卡。** 新用户只学过少量新词，这些新词的 `next_review_at` 还没到期。需要等到 SRS 间隔到期后才会有 due 卡可复习。
  
  另一个可能：如果用户在学新字时没有完成评分（没有点重来/困难/稳定/熟练），`user_cards` 表不会有记录，自然也不会有 due 卡。
- **建议修复**:
  1. 首先确认用户是否确实有 due 卡（查数据库 `user_cards` 表 `next_review_at <= now()`）
  2. 如果确实有 due 但按钮不亮，排查 `StudyStatsStore` 的网络请求是否成功
  3. 建议在按钮灰色时显示提示文字"目前沒有需要復習的字"而非静默禁用

### BUG-03: 发音按钮点了没声音

- **严重程度**: P0
- **位置**: `SpeechService.swift` + iOS 系统配置
- **现象**: 学习时点发音按钮无声音
- **原因**: 代码本身没有明显 bug——`AVSpeechSynthesizer` + `AVSpeechSynthesisVoice(language: "en-US")` 是标准用法。可能的原因：
  1. **缺少 AVAudioSession 配置**: `SpeechService` 没有在 speak 前设置 `AVAudioSession.sharedInstance().setCategory(.playback)`。在某些场景下（静音开关开启、其他音频会话争抢），系统不会自动激活合适的音频会话。这是**最可能的根因**。
  2. **设备在静音模式**: iPhone 侧面静音开关打开时，`AVSpeechSynthesizer` 默认走 `.soloAmbient` 类别，会被静音开关屏蔽。
  3. **系统语音未下载**: 如果设备没有 en-US 的高质量语音包，`AVSpeechSynthesisVoice(language:)` 可能返回 nil，此时 utterance 无法发声。
- **建议修复**:
  ```swift
  func speak(_ text: String, accent: Accent = .us) {
      // 添加这两行
      try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try? AVAudioSession.sharedInstance().setActive(true)
      
      self.synth.stopSpeaking(at: .immediate)
      let utterance = AVSpeechUtterance(string: text)
      utterance.voice = AVSpeechSynthesisVoice(language: accent.rawValue)
      // ... 其余不变
  }
  ```

---

## P1：显著影响体验

### BUG-04: 设置页面深色背景看不清文字

- **严重程度**: P1
- **位置**: `SettingsView.swift` + `TujiColor.swift`
- **现象**: 设置页面卡片/section 背景太暗，文字看不清
- **原因**: `SettingsView` 使用标准 SwiftUI `List`，背景设为 `.scrollContentBackground(.hidden)` + `.background(.tujiBg)`。`.tujiBg` = `#FFFCF5`（米白色），文字用 `.tujiInk` = `#0F1A1A`（深色）。在浅色模式下没问题。
  
  **问题在 iOS 深色模式（Dark Mode）下**：
  - `List` 的 section 内部卡片（cell）默认使用系统深色背景（黑色/深灰），但 `.tujiInk` 仍然是深色 → 深底深字，看不清
  - 所有颜色定义（`TujiColor.swift`）**全部是固定 hex 值，没有适配 Dark Mode**（没有用 `Color(uiColor:)` 或 Asset Catalog 的 Light/Dark variants）
  - 这意味着整个 App 在 Dark Mode 下可能有大面积可读性问题，不仅是设置页

- **建议修复**:
  1. **快速修**: 在 `TujiApp.swift` 或 `RootView` 强制 `.preferredColorScheme(.light)`，禁用深色模式
  2. **彻底修**: 为每个颜色 token 添加 Dark Mode 变体（通过 Asset Catalog 或 `UIColor { traitCollection in ... }`）

### BUG-05: 学新字流程中"重来"后间隔过短导致 SRS 失效

- **严重程度**: P1
- **位置**: `lib/srs.ts:schedule()` 行 60-65 / `srs-test.mjs` 测试 #10
- **现象**: 新卡点"重来"后再点"穩定"，间隔变为 `TEN_MIN × 2.4 ≈ 0.017 天（~24 分钟）`，而非正常的 3 天
- **原因**: `isNew` 判定为 `state.status === "新卡" || state.intervalDays <= 0`。重来后 `intervalDays = TEN_MIN`（≈0.007），`status = "學習中"`。再次答题时 `isNew` = false（因为 status 不是"新卡"且 interval > 0），走乘法分支 → `TEN_MIN × 2.4` = 极短间隔。
- **影响**: 用户第一次遇到卡片答错，再答对后，间隔只有 24 分钟而非预期的 1-3 天。这个词很快又会出现，打断节奏。
- **建议修复**: 添加一个条件：`isNew || (state.status === "學習中" && state.intervalDays < 1)` 时走新卡分支，而非乘法分支。或者在"重来"后 `intervalDays` 设为 0 而非 TEN_MIN。

### BUG-06: studyStats 缓存 + 时区可能导致"今日新学"数据偏移

- **严重程度**: P1
- **位置**: `lib/cards-db.ts:studyStatsRaw()` todayNew 查询
- **现象**: "今日目標"进度条可能在深夜（JST 23:xx）显示错误的当日新学数量
- **原因**: `todayNew` 查询硬编码 `AT TIME ZONE 'Asia/Taipei'`（UTC+8），但用户在日本（UTC+9）。台北和东京有 1 小时时差。台北 23:00 = 东京 00:00。如果用户在东京时间 23:00-00:00 学习，会被计入台北的"明天"但东京还是"今天"，反之亦然。
- **建议修复**: 用用户设置的时区替代硬编码的 `'Asia/Taipei'`，或至少使用 `'Asia/Tokyo'` 作为日本用户的默认值。

---

## P2：可改进但不紧急

### BUG-07: 新卡队列 fetchDue 缺乏随机化

- **严重程度**: P2
- **位置**: `lib/cards-db.ts:fetchDue()` 新卡查询，`ORDER BY c.id ASC`
- **现象**: 每次学新字，顺序完全固定（按 card ID 升序）
- **原因**: 新卡排序是 `ORDER BY c.id ASC`，没有任何随机性。用户每次进入"学新字"总是从相同的下一批开始。不同主题的单词不会交叉出现（除非 card ID 本身就是交叉排列的）。
- **影响**: 学习体验单调——总是先学完一个类别再学下一个。
- **建议修复**: 改为 `ORDER BY random()` 或按类别轮转。

### BUG-08: `StudyStats.todayNew` 声明为 Optional 但后端始终返回

- **严重程度**: P2
- **位置**: iOS `UserMe.swift:StudyStats` / 后端 `studyStatsRaw()`
- **现象**: `todayNew` 在 iOS 端声明为 `Int?`（Optional），但后端始终返回该字段。不影响功能但不规范。
- **原因**: 后端 `studyStatsRaw` 总是返回 `todayNew`（不会 null）。iOS 端 `todayNew: Int?` 的 Optional 是防御性写法——如果后端偶尔没返回就 fallback 到 nil。TodayView 用 `self.studyStats.stats?.todayNew ?? 0` 兜底，所以实际不会出错。
- **影响**: 纯代码质量问题，可改为 `Int`。
- **注意**: JSON 解码实测无问题——`.convertFromSnakeCase` 策略会通过 camelCase key 直接匹配 Swift 属性 `todayNew`，不会误转。

### BUG-09: clearLearningProgress 删除顺序可能违反外键约束

- **严重程度**: P2
- **位置**: `lib/users-db.ts:clearLearningProgress()`
- **现象**: 如果 `study_logs` 有外键引用 `user_cards` 或 `user_words`，先删 `user_words` 再删 `study_logs` 可能失败
- **原因**: 当前删除顺序：`user_learned` → `user_words` → `user_cards` → `study_logs`。如果 `study_logs.word_id` 引用了 `user_words`（取决于 schema），会违反外键。不过这取决于实际的数据库 schema，可能 study_logs 没有外键约束。
- **建议修复**: 把 `study_logs` 的删除提到最前面（它是最底层的记录表）。

### BUG-10: syncFromClient 顺序写入 N 条记录效率低

- **严重程度**: P2  
- **位置**: `lib/users-db.ts:syncFromClient()`
- **现象**: 访客模式转注册时，收藏和已学单词逐条 INSERT（for 循环）
- **原因**: 每个 favorite/learned 都是独立的 `await sql` 调用。如果用户有 50 个收藏 + 100 个已学，就是 150 次 DB 往返。
- **建议修复**: 使用 `INSERT INTO ... SELECT ... FROM unnest(...)` 批量写入。

---

## P3：轻微 / 防御性

### BUG-11: SpeechService 没有 AVSpeechSynthesizerDelegate 检测发声失败

- **严重程度**: P3
- **位置**: `SpeechService.swift`
- **现象**: 如果 TTS 引擎内部失败（语音包缺失、音频会话被抢占），用户没有任何反馈
- **建议修复**: 实现 `AVSpeechSynthesizerDelegate`，在 `speechSynthesizer(_:didCancel:)` 时 log 或给用户提示

### BUG-12: studyStats 5 条并发查询可能在高并发下打满连接池

- **严重程度**: P3
- **位置**: `lib/cards-db.ts:studyStatsRaw()` 
- **现象**: 每次调用 `studyStats` 同时发 5 条 SQL。如果多用户并发请求且连接池小（max=15），可能耗尽连接。
- **影响**: 代码注释已说明 `max=15 in lib/db.ts` 时峰值扇出 5，最多 3 个用户并发就满池。但有 30 秒缓存兜底，实际触发概率低。
- **建议**: 考虑合并部分查询，或 Next.js 层面做请求合并。

### BUG-13: TodayView 主题格只显示前 4 个

- **严重程度**: P3
- **位置**: `TodayView.swift:themeTiles` (约行 207)
- **现象**: 首页主题区域 hardcode `prefix(4)`，只显示前 4 个分类
- **影响**: 如果有超过 4 个分类，用户在首页看不到。设计上可能是有意的（有"全部"按钮），但如果分类多了可以考虑可滚动。

---

## 总结

| 等级 | 数量 | 关键项 |
|------|------|--------|
| P0 | 3 | Apple登录（配置问题）、复习按钮（可能是预期行为或stats加载问题）、发音无声（缺AudioSession配置）|
| P1 | 3 | 深色模式不适配、重来后SRS间隔异常、时区硬编码 |
| P2 | 4 | 新卡顺序固定、todayNew Optional冗余、删除顺序、批量写入 |
| P3 | 3 | TTS无失败反馈、连接池风险、首页分类截断 |

**最急需行动的**：BUG-01（Apple 登录）只需 Supabase Dashboard 配置，零代码改动。BUG-03（发音无声）大概率只需加两行 AVAudioSession 代码。BUG-04（深色模式）最快修法是强制浅色模式。这三个改完，用户反馈的 4 个 bug 中的 3 个就解决了。BUG-02（复习按钮）需要确认是真 bug 还是"确实没有 due 卡"。
