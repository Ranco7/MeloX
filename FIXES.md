# MeloX 修复复核报告（FIXES）

**一句话结论**：REVIEW.md 的 143 条 ID 与 8 份批次报告 1:1 对齐（无缺失、无多余、无重复），报告声称 74 条已修复、9 条部分修复、51 条暂缓、8 条有意设计、1 条误报；复核后将 C15 从已修复降为部分修复（73 条已修复、10 条部分修复，其余状态不变）；55 个 pipeline 提交全部真实存在且文件清单与报告逐条一致，但**全部结论均为静态核对，没有编译、没有运行、没有真机验证**，本轮也没有产生任何纠错型代码提交。

> **设备反馈第二轮（2026-11-09）**：针对真实 iPad16,3 / iPadOS 27 窗口化与 Stage Manager 反馈，新增 10 个代码/测试提交与 1 个文档提交，覆盖全曲缓存、收藏按钮可见性、列表尾部间距、浮动播放器定位、缩窗崩溃加固与若干流畅度问题。**仍未编译、未运行、未真机验证**；崩溃类结论明确标注为假设。详见第 11 节。

## 目录

1. [复核范围与硬限制](#1-复核范围与硬限制)
2. [总览](#2-总览)
3. [批次审计](#3-批次审计)
4. [ID 覆盖与合并说明](#4-id-覆盖与合并说明)
5. [逐项结论](#5-逐项结论)
6. [暂缓项汇总](#6-暂缓项汇总)
7. [已知编译与设备风险](#7-已知编译与设备风险)
8. [建议验证顺序](#8-建议验证顺序)
9. [提交清单](#9-提交清单)
10. [未做与未验证事项](#10-未做与未验证事项)
11. [设备反馈第二轮（device round 2）](#11-设备反馈第二轮device-round-2)

## 1 复核范围与硬限制

- **只是静态复核**：本环境没有 Swift 工具链、没有 Xcode、没有 iOS/macOS/watchOS 设备与模拟器、没有签名环境，无法编译、无法运行、无法抓包、无法做视觉回归。
- **未验证项**：编译、链接、类型检查、单元/回归测试、Instruments/性能测量、真机 UI 与无障碍、App Store 校验、CI 运行、网络与第三方歌词源行为、Keychain/沙盒/entitlements 行为。
- **报告是"主张"而非证据**：`.fix/reports/b1-audio-playback.json` … `b8-arch.json` 里 `root_cause`/`change`/`verification`/`risk`/`manual_test` 均由执行批次静态阅读代码后填写；本轮复核逐条比对了报告、REVIEW.md、实际 diff、调用方与部分源码，但**没有新增编译或运行证据**。
- **已核对的内容**：git 范围（base/HEAD/提交数/文件数/diffstat/`git diff --check`）、55 个提交的 subject 与文件清单、报告 ID 集合、每批状态、关键改动区域与调用点、部分被报告点名的源码位置。
- **未改动的内容**：REVIEW.md、`.fix/`（含 8 份报告）、`.agent-notes.md`、源码、工程文件、CI 均未修改；只新增 FIXES.md 的本地文档提交与后续 C15/证据归因校正；未推送。
- **本文件的定位**：对"改了什么、没改什么、还剩什么、哪些是风险但未证实"的存档式说明，供后续编译与真机验证使用。

## 2 总览

| 项目 | 值 |
| --- | --- |
| base | `b59457f2c4705d2543350e0a43800929c2fe159d` |
| pipeline HEAD（以下代码统计不含后续文档提交） | `6bf84314d33f6cd5e2727d012ebae3d7141f1a1c`（短 `6bf8431`） |
| 提交数 | 55 |
| 改动文件数 | 67 |
| diffstat | +1566 / −452 |
| `git diff --check` | 通过（无空白错误） |
| 范围内 REVIEW.md / `.fix/` 改动 | 无 |
| REVIEW 唯一 ID | 143 |
| 报告唯一 ID | 143（1:1 覆盖，缺失 0、多余 0、重复 0） |
| 原始报告状态 | fixed 74、deferred 51、partially_fixed 9、intentional 8、false_positive 1（合计 143） |
| 复核后状态 | fixed 73、deferred 51、partially_fixed 10、intentional 8、false_positive 1（C15 降级，合计 143） |
| 纠错型代码提交 | **0**（未发现可安全落地、又无需编译验证的明确代码缺陷） |
| 文档提交 | `65b2336` 首次说明 + 后续 C15/证据归因校正（均仅 FIXES.md；未推送；最终 SHA 见 `git log`） |

**每批条目 / pipeline 提交 / 复核后状态**

| 批次 | 条目 | 提交 | 状态分布 |
| --- | --- | --- | --- |
| b1-audio-playback | 8 | 3 | fixed 6、deferred 1、intentional 1 |
| b2-listen-together | 16 | 3 | fixed 14、partially_fixed 1、deferred 1 |
| b3-ipad-ui | 18 | 8 | fixed 16、deferred 1、intentional 1 |
| b4-perf-hot | 10 | 4 | fixed 7、deferred 2、partially_fixed 1 |
| b5-downloads-network | 14 | 11 | fixed 11、partially_fixed 1、deferred 1、false_positive 1 |
| b6-perf-views | 21 | 12 | fixed 6、partially_fixed 6、deferred 8、intentional 1 |
| b7-sec-build-l10n | 25 | 7 | fixed 7、deferred 16、intentional 2 |
| b8-arch | 31 | 7 | fixed 6、deferred 21、partially_fixed 1、intentional 3 |
| **合计** | **143** | **55** | **fixed 73、deferred 51、partially_fixed 10、intentional 8、false_positive 1** |

## 3 批次审计

### b1-audio-playback（8 条 / 3 提交）

- **状态**：6 fixed（A0、A7、A14、A22、B7、B14）、1 deferred（A21）、1 intentional（A8）。
- **结论**：3 个提交（`ebbb733`、`36f1e0c`、`13c1632`）真实存在，共触及 6 个文件，与报告清单一致。
- **差异**：该批次会话没有 shell/编译器，只能逐段回读；A8 判定为有意设计（`PlayerStore.swift:1194-1196` 注释说明 `/song/enhance/player/url/v1` 可能返回 HTTP 200 + null URL，需同曲重试，最多 3 次、退避 400/800ms）；A21 的"静音 seek"同样是有意行为，补超时/取消属独立增强。
- **残余风险**：A0 的 `setCategory` 用 `try?` 包裹，切换失败时仍停在 `.playAndRecord`；恢复瞬间可能有一次路由切换。

### b2-listen-together（16 条 / 3 提交）

- **状态**：14 fixed、1 partially_fixed（B1）、1 deferred（B0）。
- **结论**：3 个提交（`1ef4f65`、`8f548c2`、`f5e4080`）与报告一致；A18 由**两个提交**共同覆盖（`1ef4f65` 增加 leaving guard，`8f548c2` 复用同一守卫）。
- **差异**：B1 只做到"首次观察到实际应用"之间的耗时补偿——协议命令只有 `progressMilliseconds`，没有发出时间戳，首次观察之前已经流逝的时间无法补偿；彻底修复需要协议时间戳或可靠的 heartbeat `timeSpan` 校正。B0（会话内单曲循环把房间拉回开头）按产品/协议决策暂缓。
- **残余风险**：B9 已修复但仍有启动竞态——`restore()` 在 `hasRestoredPlayback` 时提前返回，可能不会 await 一次进行中的 restore；A16 的新校验依赖"`data:null` 表示未确认"这一报告结论。

### b3-ipad-ui（18 条 / 8 提交）

- **状态**：16 fixed（E0、B3、E1、E3、E4、E5、E7、E6、B12、B15、B17、E10、E12、E13、E14、E16）、1 deferred（E15）、1 intentional（E9）。
- **结论**：8 个提交（`36218a3`、`911514d`、`7c961aa`、`1bc0c53`、`a4bedfa`、`8cb0817`、`9f552e7`、`06aa68f`）真实存在，文件清单与 diff 完全匹配。
- **差异（运行器异常）**：首次运行 `rc=127` 且 jsonl 为空，唯一错误是 `.fix/run.sh: line 11: its: command not found`——这是 runner 脚本的拼写错误，**不是 Swift 编译输出**，不能据此推断代码正确或错误；现存报告与 8 个提交均为真实产物。现有记录不足以证明 b3 曾完整重跑，故不补写重跑历史。
- **残余风险**：E1 使用了报告允许的"至少限制封面"替代方案（居中大幅封面，而非左右分栏），并且仍以 `wideArtistColumnWidth: nil` 调用 `trackContent`，排行榜曲目行仍是窄行；B12 新增私有 `SidebarArtworkResult(@unchecked Sendable)` 承载跨任务传递的 `UIImage`，并让包含 UIKit 图像的结果字典经过 task group 边界；其实际 Sendable/隔离诊断取决于 SDK 与 Swift 编译设置；本批报告建议优先编译 `PlaylistDetailContent.swift` 与 `ContentView.swift`。

### b4-perf-hot（10 条 / 4 提交）

- **状态**：7 fixed（C1、A9、C4、C2、C22、C6、C13）、2 deferred（C0、A13）、1 partially_fixed（C3）。
- **结论**：4 个提交（`be0fcb7`、`6242a88`、`aa3b4c5`、`8edce1a`）与报告一致；C1/A9/C4/C2 因共享 `PlayerStore.swift` 等文件合并为一个提交。
- **差异**：C3 只做了 60fps 上限，`maxSampleOffset` 与 `drawingGroup` 明确未改（报告说明缩小采样偏移会引入边缘错误、`drawingGroup` 与 `layerEffect` 组合可能改变合成结果，需真机验证）。
- **残余风险**：C1 依赖可选三元与类型推断（`?:`）能否通过编译；C3 的视觉/发热需真机对比。

### b5-downloads-network（14 条 / 11 提交）

- **状态**：11 fixed、1 partially_fixed（D15）、1 deferred（A11）、1 false_positive（A12）。
- **结论**：由 fast 模型执行，产出 11 个真实提交、每个提交 1 个文件，逐条与报告文件清单一致（`156a008`、`94275bc`、`fa7c3a7`、`0114bec`、`bd3cac0`、`851581a`、`ff03f6a`、`4556bcc`、`7329c02`、`4fe619b`、`d2b1412`）。
- **差异（误报）**：A12 经复核为**确认误报**——`Self.scope(for: settings.cookie)` 在 async actor 调用/await 之前求值，scope 在 actor hop 前已按当前 cookie 固定；三个调用方（`LibraryStore.persistContent`、`HomeRecommendedView.persistContent`、`PlaylistDetailView.persistContent`）都在 await 后按请求发起时的 token 做了 guard。因此未改代码。
- **残余风险**：D15 只补了日志，没有 UI 错误通道、也没有保留上次缓存；`QQMusicLyricMatchStore` 的 actor/static 隔离（D21）需编译确认；`A5`/`B4` 占位实现使用 `Song(id:name:artists:)` 与 `Set.subtract([Int])`，类型是否成立未编译验证。

### b6-perf-views（21 条 / 12 提交）

- **状态（复核后）**：6 fixed（C8、C17、C20、C21、C24、C25）、6 partially_fixed（C7、C12、C14、C15、C26、C28）、8 deferred（C5、C9、C10、C11、C16、C18、C19、C23）、1 intentional（C27）。
- **结论**：首次 fast 运行**没有留下报告、也没有落地任何编辑**（状态为 NO REPORT）；重新排队 flash/high 运行后产生 12 个真实提交（`350c745`、`05433aa`、`fdb7c08`、`36570c7`、`ea99562`、`c6c0697`、`b624849`、`1031ffa`、`01810aa`、`ad6173c`、`640740f`、`6bf8431`），全部与报告一致。
- **差异**：无缺失提交；原报告 5 条部分修复之外，本轮把 C15 从 fixed 降为部分修复：父级 GeometryReader 仍可重建子视图并重算 composition，不能把 View init 的 let 称为持久缓存。
- **残余风险**：C15 只是把 `composition` 提升为 View 的 `private let`（只移出子视图自身的 GeometryReader），父视图 body 重建仍会重算，不是持久缓存；C25 把 `ForEach` 身份从 `song.id` 改为 `indices`（行内仍显式 `.id(song.id)`），插入/删除/重排时的容器身份需真机确认；C20 并发时首个调用者的 `fallbackPrefersDarkAppearance` 会被共享。

### b7-sec-build-l10n（25 条 / 7 提交）

- **状态**：7 fixed（F3、F4、F5、F6、F13、F20、F23）、16 deferred（F0、F1、F2、F7、F8、F9、F10、F11、F15、F16、F17、F18、F19、F21、F22、B13）、2 intentional（F12、F14）。
- **结论**：7 个提交（`5c5e8a7`、`479579e`、`225b104`、`2940ba3`、`ea5936f`、`f46b09b`、`d3ef15f`）与报告一致；F5/F6 的报告 files 与 change 均明确包含 iOS、MeloXDesktop 两份实现，实际提交与之相符，不存在未报告的范围扩展。
- **差异**：无缺失/多余提交；F12（`screen-capture` 后台模式）与 F14（手表独立语言）判定为有意设计，未改。
- **残余风险（是风险，不是已证实缺陷）**：F5 要求登录 Cookie 的 domain 必须等于 `music.163.com`，若登录流程把 `MUSIC_U` 写在 `.163.com` 上，登录会一直等待；F6 要求 NOS LBS 上传地址为 `https` 且命中 `127.net/126.net/netease.com/163.com/163yun.com`（含子域）白名单，新 CDN 或 IP 会让云盘上传以 `requestEncoding` 失败，且只校验初始 URL、不校验重定向目标；F20 的 DEBUG `assertionFailure` 在任一 target 缺 lproj 时会崩溃。

### b8-arch（31 条 / 7 提交）

- **状态**：6 fixed（D22、D24、D27、D28、D29、D32）、1 partially_fixed（D17）、21 deferred、3 intentional 亮点（E17、E18、E19）。
- **结论**：7 个提交（`82a8047`、`56d179a`、`956ead6`、`220e7b4`、`66ffb04`、`6895b7e`、`31830a7`）真实存在，共 14 个既有源文件，与报告"仅修改 14 个既有源文件、未新增文件"一致。
- **差异**：D17 只完成依赖注入（新增 `SongRecognitionRecording` / `AudioFingerprintGenerating` 协议与 `init(recorder:fingerprintGenerator:)`），**Store 生命周期仍跟随 View**，未达到报告期望的 Environment 注入，故为部分修复。
- **残余风险**：D24 的多行前导 `*` 运算符写法被 tree-sitter 语法检查在 1 处额外报出 2 条诊断（与基线既有同类写法一致，属语法分析器限制，不是已确认的编译错误）；D28 删除 iOS 未使用 API 后若后续需要需重新添加。

## 4 ID 覆盖与合并说明

- **覆盖**：REVIEW.md 中反引号 ID 共 143 个唯一值；8 份报告 `items[].id` 合计 143 个唯一值；两者**集合完全相同**，`missing_review_ids`、`extra_report_ids`、`duplicate_ids` 均为空。
- **按设计缺席的合并别名**（REVIEW.md 已把它们并入主条目，因此既不在 143 个 ID 中、也不应出现在报告里）：`A4 = B2`、`A6 = B4`、`A26 = B12 = E8`、`E2 = B3`、`E11 = B17`、`D0 / D1 = A9`。
- **无重复**：每份报告内部 `unique_item_ids == item_count`，跨批次也没有同一 ID 出现在两个批次。
- **分批归属**：b1 8、b2 16、b3 18、b4 10、b5 14、b6 21、b7 25、b8 31，合计 143。
- **提交归属**：有 83 个 ID 关联到实际提交（74 fixed + 9 partially_fixed 全部有提交）；60 个 deferred/intentional/false_positive 条目不产生提交。只有 A18 同时由两个提交覆盖。

## 5 逐项结论

以下每节对应 REVIEW.md 的一个 ID，状态标签以复核结论为准：C15 从原报告 fixed 降为部分修复；A12 维持原报告的误报结论。"提交"为该 ID 关联的真实短 SHA；"静态核对，未编译"表示只做了代码/调用方阅读，没有任何编译或运行证据。

## 5.1 b1-audio-playback（8 条）

### A0 已修复

- **结论**：连续识别结束后音频会话卡在 `.playAndRecord`，已在停止识别时显式恢复 `.playback`。
- **原因**：`activate()` 对 `.playAndRecord` 直接 return，既不恢复 category 也不 `setActive`，之后每次 load/play 都提前返回。
- **改动**：`stopAudioSession()` 中若 category 为 `.playAndRecord`，先按 `preferredMixMode` 计算 options 并 `setCategory(.playback, mode: .default)`，再走原有 activate/`setActive(false)` 分支；录音中仍保持 `.playAndRecord`。
- **文件**：`MeloX/Features/SongRecognition/SongRecognitionAudioRecorder.swift`
- **提交**：`ebbb733`
- **验证**：回读 61-104、201-253 及 `SongRecognitionStore` 调用点，确认停止后无路径把 category 改回 playback；静态核对，未编译。
- **手测**：蓝牙耳机下连续识别并播放结果后停止，确认回 A2DP、麦克风指示熄灭、混音设置生效。
- **风险/遗留**：`setCategory` 用 `try?` 包裹，失败时仍保留 playAndRecord；恢复瞬间可能有路由切换/短暂中断。

### A7 已修复

- **结论**：队列播完时 `seek(0)` 会重新拉流再暂停，已改为 stopped 状态只记录位置。
- **原因**：EOF 时 AudioStreaming 置 `.stopped`，`stopAtQueueEnd` 先 pause 再 `seek(0)`，`Deck.seek` 命中 stopped 分支再次 `play(url:)`；`cancelAutoMixPreparation()` 还会把 rate 设为 1 触发同一路径。
- **改动**：`Deck.seek` 在 stopped 且 `!wantsPlayback` 时只记录 `initialSeek` 并保持 paused；`Deck.play` 在 stopped 时 seek 到 `initialSeek ?? 0`；`stopAtQueueEnd` 把 `engine.pause()` 提到 `cancelAutoMixPreparation()` 之前。
- **文件**：`MeloX/Core/Playback/Engine/AudioPlaybackDeck.swift`、`MeloX/Core/Playback/Session/PlayerStore.swift`
- **提交**：`13c1632`
- **验证**：读 Deck 101-150/220-230、PlayerStore 1306-1319、AutoMix 取消路径与 vendor EOF 语义，确认三条触发路径均覆盖；静态核对，未编译。
- **手测**：关闭循环与自动播放播完整张专辑，结束瞬间不应有 loading/额外请求；按播放应从第一首 0 秒开始。
- **风险/遗留**：EOF 后暂停状态下的 seek 不再立即起流（预期）；若 vendor 改变 EOF 状态语义，stopped 判断需同步调整。

### A8 暂缓（有意设计）

- **结论**：版权/会员不可用歌曲最多重试 3 次（约 1.2 秒）是刻意设计，未改代码。
- **原因**：`/song/enhance/player/url/v1` 首次可能返回 HTTP 200 + null URL，与会员/版权/地区不可用无法区分，故 `.noPlayableSource/.emptyResponse/.invalidResponse` 与 5xx、URLError 一起视为可重试（退避 400/800ms）。
- **改动**：未改代码；`PlayerStore.swift:1194-1196` 的注释已说明该权衡。
- **文件**：—（报告引用 `MeloX/Core/Playback/Session/PlayerStore.swift`）
- **提交**：—
- **验证**：读 1194-1245 的注释、循环与错误分类，确认重试集合与退避参数是为 null URL 场景设置；静态核对，未编译。
- **手测**：播放仅会员可用歌曲，确认约 1.2 秒后弹错；弱网首次 null URL 应自动恢复。
- **风险/遗留**：无（未改动）。

### A21 暂缓

- **结论**：暂停意图已由 `wantsPlayback` 记录并在 seek 完成时兑现，真正缺的是 seek 超时/取消与失败上报，未改代码。
- **原因**：`AudioPlaybackDeck.pause()` 在 `isSeeking` 时只置 `wantsPlayback=false` 以保持静音解码；`audioPlayerStateChanged` 再按 `wantsPlayback` 暂停并恢复音量。
- **改动**：未改代码；补超时需要新的错误语义与播放器清理策略，属独立增强。
- **文件**：—（报告引用 `MeloX/Core/Playback/Engine/AudioPlaybackDeck.swift`）
- **提交**：—
- **验证**：读 pause/seek/`audioPlayerStateChanged` 与 `currentPlaybackTime` 的 isSeeking 保护，确认静音解码是有意行为；静态核对，未编译。
- **手测**：弱网/坏源下拖动进度条立即暂停，确认 seek 落定后进入暂停；seek 长时间不返回时仍会继续静音加载（已知限制）。
- **风险/遗留**：seek 卡住时点暂停无法立即停止传输。

### A22 已修复

- **结论**：`resumeInPlace` 激活会话失败不再静默返回，改走 `fail(with:)`，UI 不再假装在播放。
- **原因**：`activate()` 抛错时 catch 直接 return，既不回滚 `wantsPlayback` 也不触发 `onFailure`，Now Playing 仍显示播放。
- **改动**：catch 改为 `fail(with: AudioPlaybackError.audioSession(error))` 后 return，与 play/load 错误路径一致；`fail` 会回滚 `wantsPlayback`、暂停 decks 并触发 `onFailure` 设置 `playbackIssue`。
- **文件**：`MeloX/Core/Playback/Engine/AudioPlaybackEngine.swift`
- **提交**：`36f1e0c`
- **验证**：读 119-152、`fail(with:)` 238-246 与 `PlayerStore.handleEngineFailure` 的 `.audioSession` 分支；静态核对，未编译。
- **手测**：播放中制造 activate 失败（来电打断/切换混音策略），确认停止播放并显示错误而非无声假装播放。
- **风险/遗留**：从静默失败变为显式报错（预期）；`didReportCurrentItemFailure` 保持到下一次 load/unload。

### B14 已修复

- **结论**：切换"与其他 App 混音"时异步中断通知不再被当成真实中断而暂停播放。
- **原因**：`activate()` 用同步 `isApplyingConfiguration` + defer 保护 `setCategory`，但中断通知经 `NotificationCenter(queue: .main)` 异步投递，回调执行时标志已清为 false，guard 永不成立。
- **改动**：真正执行 `setCategory` 时记录 `lastConfigurationDate`，新增 `shouldIgnoreInterruption()`（同步标志或距最近一次 category 变更 < 0.5 秒）；`handleAudioInterruptionBegan` 改用该函数。
- **文件**：`MeloX/Core/Playback/Engine/AudioPlaybackSessionConfigurator.swift`、`MeloX/Core/Playback/Session/PlayerStore.swift`
- **提交**：`13c1632`
- **验证**：读 activate 的 defer、engine observer 注册与旧 guard，确认异步回调晚于 defer；新函数在 `@MainActor` 读写静态时间戳；静态核对，未编译。
- **手测**：播放中反复开关"始终与其他 App 混音"，音乐不应暂停；再触发真实中断（来电/Siri）确认仍能暂停并恢复。
- **风险/遗留**：切换 category 后 0.5 秒内到达的真实中断会被忽略，极端情况下可能在来电期间保持 playing。

### A14 已修复

- **结论**：`goTo` 上报移到音源解析成功之后，解析失败补发 pause，房间不再误以为本机在播放新歌。
- **原因**：`loadCurrentSong` 在 await 音源解析之前就发 `.goTo`，此时 `isLoading=true`、`listenTogetherReportedPlaying` 为真；解析失败只设 `playbackIssue`，不再发 pause/error。
- **改动**：`.goTo` 移到 `isResolvingSource=false` 之后、`engine.load` 之前；解析失败 catch 中当 `reportsToRoom` 为真时补发 `.pause`；为保持 `Tools/Tests` 源码抽取 harness 可编译，在 `TransportCommand` stub 增加 pause。
- **文件**：`MeloX/Core/Playback/Session/PlayerStore.swift`、`Tools/Tests/test_playback_song_switch.py`
- **提交**：`13c1632`
- **验证**：读 PlayerStore 1095-1192、PlayerEvents 5-40、Store 163-171，确认成功路径仍只发一次 goTo、失败路径不再发 goTo；静态核对，未编译。
- **手测**：两台设备同房间，在 A 上点无版权/会员歌曲，确认 B 不会短暂显示该曲在播放且最终暂停；再点可播放歌曲确认 goTo 正常。
- **风险/遗留**：goTo 会晚几百毫秒到数秒；失败时 PAUSE 的 targetSongID 是本机不可用歌曲，若服务端要求目标在房间歌单内可能被拒。

### B7 已修复

- **结论**：引擎最终失败与音频中断现在会向房间上报 pause，自动恢复补发 play，房间状态不再停留在"在播放"。
- **原因**：fork 删掉了 `ListenTogetherAppCoordination` 对 `player.isPlaying` 的 onChange 统一上报；`handleEngineFailure` 最终失败分支与 `handleAudioInterruptionBegan` 直接改状态/`engine.pause()`，不上报。
- **改动**：最终失败分支在置 `isLoading/isPlaying=false` 后发 `.pause`；中断开始时记录 `wasActive`，`engine.pause()` 后仅在 `wasActive` 时发 `.pause`；中断结束自动恢复时发 `.play`。
- **文件**：`MeloX/Core/Playback/Session/PlayerStore.swift`
- **提交**：`13c1632`
- **验证**：读 PlayerStore 1258-1304、1396-1418 与 `bindEngine` 绑定，确认重试分支只在真正最终失败后上报；静态核对，未编译。
- **手测**：两台设备同房间，在 A 上制造播放失败/来电中断，确认 B 显示暂停；中断结束 A 自动恢复后 B 也恢复。
- **风险/遗留**：房间是全局播放状态，任一成员通话/失败会暂停全房间（恢复 fork 前行为）；若产品要求仅本机静音则不应合入。

## 5.2 b2-listen-together（16 条）

### B1 暂缓（部分已修复）

- **结论**：已补偿"首次观察命令"到"实际应用"之间的耗时，但协议无命令时间戳，首次观察前的 age 仍无法补偿。
- **原因**：`synchronizeFromServer` 把 `progressMilliseconds` 直接当当下位置；`loadSongsPreservingOrder` 的批量 songDetails 与音源解析耗时没有补偿，同一命令重复应用也从旧 progress 重来。
- **改动**：新增 `ListenTogetherObservedPlayCommand` 与 `observedPlayCommand`：按命令签名记录首次观察时间；应用时若签名一致且为播放态，用 `progress + (now - observedAt)`（`max(0, …)` 防负）；establishSession/clearSession 重置。
- **文件**：`MeloX/Core/Playback/Session/ListenTogetherStore+Synchronization.swift`、`MeloX/Core/Playback/Session/ListenTogetherStore.swift`
- **提交**：`1ef4f65`
- **验证**：读 models 295-303（命令无时间戳）、Synchronization 97-242、PlayerEvents 175-198 与 `PlayerStore.synchronizeListenTogetherPlayback` 385-459；静态核对，未编译。
- **手测**：播放中杀 App 重启或从邀请链接加入，观察起播位置是否更接近房主；让对方切歌/seek，确认不再固定落后。
- **风险/遗留**：加入/恢复房间时命令本身可能已发出数秒，这部分仍无法校正；若服务端动态刷新 progress，补偿会略超前。

### B2 已修复

- **结论**：本地命令发送失败会回填并按 1/2/4/8s 退避重试，重试期间不再应用远端旧命令，暂停/切歌不再被弹回。
- **原因**：发送前就把 `pendingTransportReport` 置 nil，catch 只设 `.reconnecting`，命令永久丢失；随后轮询把房间旧命令当远端命令套回本机。
- **改动**：改为带 1s/2s/4s/8s 退避的重试循环；失败且期间没有更新报告时把刚失败的报告放回队列；重试期间 `transportReportTask` 保持非 nil，`synchronizeFromServer` 继续跳过远端命令。
- **文件**：`MeloX/Core/Playback/Session/ListenTogetherStore+PlayerEvents.swift`
- **提交**：`8f548c2`
- **验证**：读 PlayerEvents 42-92 与 Synchronization 97-101 的互斥条件；静态核对，未编译。
- **手测**：弱网下在房间内暂停/切歌/seek，恢复网络后确认房主能看到操作且本机不被旧命令弹回。
- **风险/遗留**：房间已结束或命令被服务端持续拒绝时会每 8s 重试到会话清理；退避期间连接状态可能被其他成功请求覆盖为 connected（非瞬态服务端拒绝可无限重试）。

### B4 已修复

- **结论**：目标歌曲无法解析时不再每秒重试并永久卡在"正在恢复连接"，改为占位/回退并更新签名。
- **原因**：`guard songs.contains(targetSongID)` 在两个 signature 更新之前抛错，pollServer 每秒用同一 payload 重试；`loadSongsPreservingOrder` 又用 `compactMap` 丢弃缺失 ID。
- **改动**：缺失 ID 生成占位 `Song` 并记入 `unresolvedSongIDs`；transport 分支发现目标缺失/占位时回退到歌单第一个已解析歌曲并把 progress 置 0；全部不可解析时先更新签名再返回，所有提前返回都写签名。
- **文件**：`MeloX/Core/Playback/Session/ListenTogetherStore+Synchronization.swift`、`MeloX/Core/Playback/Session/ListenTogetherStore.swift`
- **提交**：`1ef4f65`
- **验证**：读 Synchronization 140-242、`playbackSongIDs` 与 MusicModels:256 的 `Song` 初始化器，逐条核对提前返回的签名更新；静态核对，未编译。
- **手测**：让房主队列加入一首本机下架/无版权歌曲并播放它，确认 UI 不再永久显示正在恢复连接，本机退到第一首可播放歌曲且不再每秒请求。
- **风险/遗留**：回退会换歌（报告建议的降级）；占位 Song duration 为 0、名称为本地化"未知歌曲"，若成为当前歌曲会走既有播放失败提示。

### B8 已修复

- **结论**：纯歌单变化不再把房间已删除的当前歌曲 append 回本地队列，改为对齐房间新队列并暂停。
- **原因**：纯歌单路径 `appliesTransport` 为 false，但 `targetSongID` 仍回落到 `player.currentSong?.id` 并无条件 `songIDs.append(targetSongID)`，本地编辑又把它当快照上报，抵消房主删除。
- **改动**：append 仅在 `appliesTransport` 为真时执行；纯歌单路径下若当前歌不在新歌单，改为 `synchronizeListenTogetherPlayback` 对齐新队列并暂停在第一个可解析歌曲（progress 0、不上报房间）；末尾统一更新签名。
- **文件**：`MeloX/Core/Playback/Session/ListenTogetherStore+Synchronization.swift`
- **提交**：`1ef4f65`
- **验证**：读 Synchronization 141-167 与 PlayerStore 382-481，确认 append 条件与两条队列替换路径；静态核对，未编译。
- **手测**：房主删除成员 A 正在播放的歌曲，A 端应暂停并显示房间新队列；随后任一成员编辑队列，已删除歌曲不应被带回。
- **风险/遗留**：删除当前歌曲时本机会停止播放并换到歌单第一首；下一次心跳会把暂停状态报给房间。

### A5 已修复

- **结论**：部分歌曲解析失败不再静默截断共享队列，改为占位保序并把完整 ID 列表上报。
- **原因**：`loadSongsPreservingOrder` 用 `compactMap` 丢弃 songDetails 没返回的 ID，songs 比 songIDs 短却不报错，随后仍记录 playlist signature；用户任意一次队列编辑都会把缩短后的队列发给全房间。
- **改动**：缺失 ID 生成占位 `Song`（保留 id、名称用既有 `ui.metadata.unknown_song`），保持顺序与长度；`unresolvedSongIDs` 记录待重解析；快照上报不再缺项。
- **文件**：`MeloX/Core/Playback/Session/ListenTogetherStore+Synchronization.swift`、`MeloX/Core/Playback/Session/ListenTogetherStore.swift`
- **提交**：`1ef4f65`
- **验证**：读 Synchronization 244-279、PlayerEvents 141-160 与 `Song` 初始化器；静态核对，未编译。
- **手测**：房间歌单放入当前账号不可用的歌曲，编辑本地队列后让房主查看共享队列，确认 ID 未被截断；重启后占位仍保留该 ID。
- **风险/遗留**：占位歌曲可能进入队列并持久化，播放到会触发既有失败提示；`Song(id:name:artists:)` 与 `Set.subtract([Int])` 的类型是否成立未编译验证。

### B5 已修复

- **结论**：轮询改为播放 1s、暂停 5s、失败 2/4/8s 退避，暂停时不再保持 1Hz 全量拉取。
- **原因**：`monitorSession` 固定每 1s 调 `pollServer`，无论播放/暂停/失败都拉完整 `listenTogetherPlayback` 并重算 playlist signature。
- **改动**：轮询节奏按播放 1s、暂停 5s；失败按 2/4/8s 退避；`pollServer` 改为返回 `Bool`；房间状态与心跳在播放时每 5 次轮询（约 5s）发送、暂停时每 2 次（约 10s）发送。
- **文件**：`MeloX/Core/Playback/Session/ListenTogetherStore+Synchronization.swift`
- **提交**：`1ef4f65`
- **验证**：读 Synchronization 11-72，确认 `pollServer` 所有路径都返回 Bool、签名不变时首个 guard 跳过；静态核对，未编译。
- **手测**：房间内播放和暂停，用抓包观察请求频率；弱网确认间隔按 2/4/8s 增长。
- **风险/遗留**：暂停时远端恢复最多延迟 5s；暂停心跳约 10s（原约 5s），若服务端超时更短需回调节奏；失败重试最长 8s 一次。

### B6 已修复

- **结论**：房间 playMode 变化不再被当作歌单变化消费掉，会真正应用到本机（受 `listenTogetherPlayModeTouched` 保护）。
- **原因**：`signature(for: playlist)` 包含 playMode，playMode 变化令 `playlistChanged` 为真；但非 initial 分支只调 `synchronizeListenTogetherQueue(songs:)`，完全不读 playMode，随后写入新签名。
- **改动**：`synchronizeListenTogetherQueue` 增加 `playMode` 参数（默认 nil，旧调用兼容），在 `!listenTogetherPlayModeTouched` 时调 `applyListenTogetherPlayMode`；同步侧传入 `payload.playlist?.playMode`；transport 分支 `adoptsRoomPlayMode` 改为 `initial || playlistChanged`。
- **文件**：`MeloX/Core/Playback/Session/ListenTogetherStore+Synchronization.swift`、`MeloX/Core/Playback/Session/PlayerStore.swift`
- **提交**：`1ef4f65`
- **验证**：读 Synchronization 281-292 与 PlayerStore 461-481、496-509，确认唯一调用方已更新；静态核对，未编译。
- **手测**：房主中途切换房间播放模式，成员端应同步；成员手动切换后再由别人改模式，应保持成员自己的选择。
- **风险/遗留**：其他成员改模式会改变本机 `repeatMode`（用户手动改过后受 touched 保护）；纯队列更新也会幂等应用一次模式；映射只覆盖 SINGLE/LOOP。

### B10 已修复

- **结论**：队列快照上报失败会按 1/2/4/8s 退避重试，重试期间不会被远端旧队列覆盖本地编辑。
- **原因**：350ms 防抖后的 `sendPlaylistSnapshot` 失败只设 `.reconnecting` 不重排；下一轮 `synchronizeFromServer` 拿到服务器旧歌单直接覆盖用户刚做的编辑。
- **改动**：`queueReportTask` 内改为重试循环：保留 350ms 防抖，失败后 1/2/4/8s 退避，每次校验 `sessionRevision`、`queueReportRevision` 与 `leaving`；任务存在期间 `synchronizeFromServer` 因 `queueReportTask != nil` 跳过远端覆盖。
- **文件**：`MeloX/Core/Playback/Session/ListenTogetherStore+PlayerEvents.swift`
- **提交**：`8f548c2`
- **验证**：读 PlayerEvents 94-139 与 Synchronization 100-101，确认每次编辑 `queueReportRevision += 1` 并取消旧任务；静态核对，未编译。
- **手测**：弱网下添加/拖动队列，断网再恢复，确认编辑最终上报且本地队列不回滚。
- **风险/遗留**：服务端持续拒绝时会每 8s 重试并阻塞远端同步，直到再次编辑或离开房间（非瞬态拒绝可无限重试）。

### B11 已修复

- **结论**：房间状态响应缺少 roomId 时不再误判"账号已切换"并退出房间。
- **原因**：`ListenTogetherRoom` 解码时 roomId 缺失退化成空串，`refreshRoomStatus` 用 `updatedRoom.id == expectedRoom.id` 判断换房，空 id 立即判为换房并 `clearSession`。
- **改动**：仅当 `updatedRoom.id` 非空且与 `expectedRoom.id` 不同才判定换房；空 id 视为未变化，保留 `expectedRoom` 作为当前 room，`isHost` 按实际采用的 room 计算。
- **文件**：`MeloX/Core/Playback/Session/ListenTogetherStore+Synchronization.swift`
- **提交**：`1ef4f65`
- **验证**：读 models 35-73、Synchronization 74-95 与 `restoreSession` 对空 id 的既有处理；静态核对，未编译。
- **手测**：模拟 roomStatus 响应缺 roomId，确认 UI 不再误报账号已切换；后续完整响应仍能识别真正换房。
- **风险/遗留**：服务端确实换房但响应缺 roomId 时不会立即退出，会等下一次完整响应（比误退更保守）。

### B16 已修复

- **结论**：清空队列不再抛 `noCurrentSong` 并被当成连接故障，界面不再显示"正在恢复连接"。
- **原因**：清空队列时 `sendPlaylistSnapshot` 抛 `noCurrentSong`，`playerQueueDidChange` 的 catch 把它与网络错误一样处理，直接设 `.reconnecting`。
- **改动**：`displaySongIDs` 为空时直接 return，不再抛 `noCurrentSong`；重试循环正常结束。
- **文件**：`MeloX/Core/Playback/Session/ListenTogetherStore+PlayerEvents.swift`
- **提交**：`8f548c2`
- **验证**：读 PlayerEvents 141-148 与 94-139，确认其他失败仍进入重试；静态核对，未编译。
- **手测**：房间内清空播放队列，确认不再出现正在恢复连接提示。
- **风险/遗留**：空队列不会上报给房间（协议不支持空 displayList），房间保持旧歌单直到下一次有效编辑。

### A16 已修复

- **结论**：data 为 null 的动作回执不再被当作成功，改为抛 `APIError.server` 并进入重试/提示。
- **原因**：`validateListenTogetherAction` 只在 `data.result == false` 或 `data.success == false` 时抛错；code 200 且 data 为 null 时两个 optional 都为 nil 被当成功，而 `sendCommand` 已把 clientSequence 记入本地回执，后续真正回执会被抑制。
- **改动**：增加 `guard let data = response.data`，缺失时抛 `APIError.server`（operation_incomplete）；之后再用 result/success 判断；命令上报、队列快照与心跳都走该校验。
- **文件**：`MeloX/Core/Networking/NeteaseListenTogetherAPI.swift`
- **提交**：`f5e4080`
- **验证**：读 218-239 与调用方 126-198，确认三个调用路径与 `APIError.server` 签名；静态核对，未编译。
- **手测**：构造/抓到 data:null 响应，确认命令会重试并在无法恢复时提示，而不是静默成功；同时确认正常心跳不被误判。
- **风险/遗留**：若服务端心跳成功时也返回 data:null，会被误判为失败并触发重试/重连（需抓包确认心跳响应结构）。

### A17 已修复

- **结论**：回声抑制从"最近 16 条数组"改为单调高水位，活跃用户超过窗口后不再被自己的旧回执拉回旧进度。
- **原因**：`locallyReportedCommandSequences` 固定保留最近 16 条且回执到达不删除；`sendPlaylistSnapshot` 也消耗 clientSequence，超过窗口后旧命令回执被当远程命令执行。
- **改动**：删除数组，改为 `lastLocallyReportedCommandSequence` 单调高水位；`sendCommand` 请求前更新高水位；`commandOriginatedLocally` 用 `clientSequence > 0` 且不超过高水位判断；establish/clear 重置为 0。
- **文件**：`MeloX/Core/Playback/Session/ListenTogetherStore.swift`、`MeloX/Core/Playback/Session/ListenTogetherStore+PlayerEvents.swift`
- **提交**：`8f548c2`
- **验证**：读 PlayerEvents 175-198、216-222 与 Store 135-150、385-412，确认 clientSequence 每会话从 0 单调递增；静态核对，未编译。
- **手测**：房间内连续快速切歌/seek 超过 20 次，确认不会被自己的旧回执拉回旧进度或旧歌曲。
- **风险/遗留**：高水位回显抑制假设 clientSequence 按账号独立递增；同一账号多设备同房间时，另一设备的序号若不超过本机高水位会被误判为本地回声。

### A18 已修复

- **结论**：离开房间期间不再发送心跳、也不再用 room_ended 覆盖正常离开流程。
- **原因**：`sendHeartbeat` 是唯一没有 `operation != .leaving` 判断的上报路径，`refreshRoomStatus` 也没有；`leaveRoom` 等 end 请求期间 `monitorTask` 尚未取消，轮询仍可能发心跳或触发 `clearSession(notice: room_ended)`。
- **改动**：`sendHeartbeat` 与 `refreshRoomStatus` 增加 leaving guard（调用前后各检查一次）；`leaveRoom` 开始时立即 `cancel monitorTask`，若 end 请求被取消则在返回前 `startMonitoring()` 恢复轮询。
- **文件**：`MeloX/Core/Playback/Session/ListenTogetherStore.swift`、`MeloX/Core/Playback/Session/ListenTogetherStore+Synchronization.swift`、`MeloX/Core/Playback/Session/ListenTogetherStore+PlayerEvents.swift`
- **提交**：`1ef4f65`、`8f548c2`
- **验证**：读 Store 316-339、Synchronization 74-95、PlayerEvents 200-214，并与 `synchronizeFromServer` 的 leaving guard 对照；静态核对，未编译。
- **手测**：点击离开房间，抓包确认 end 请求期间不再发 heartbeat；模拟取消后确认轮询能恢复。
- **风险/遗留**：end 请求较慢时离开期间没有心跳（预期）；取消恢复路径已补。

### A19 已修复

- **结论**：`refresh()` 增加 sessionRevision 校验，过期结果不再覆盖新会话的连接状态。
- **原因**：`refresh()` 没有像 `pollServer` 那样捕获 sessionRevision 并在 await 后比较；恢复后的代码仍把 `.connected`、`consecutiveSyncFailures = 0`、`lastSyncDate` 写到新会话上。
- **改动**：`refresh()` 进入时保存 sessionRevision，`refreshRoomStatus`/`synchronizeFromServer`/`sendHeartbeat` 每个 await 之后都 guard 相等；catch 中也先检查再设 `.reconnecting`。
- **文件**：`MeloX/Core/Playback/Session/ListenTogetherStore.swift`
- **提交**：`1ef4f65`
- **验证**：读 Store 341-361 与 Synchronization 的 `pollServer` 同模式，确认 `refreshRoomStatus` 自身也有 session guard；静态核对，未编译。
- **手测**：房间内点刷新同时切换账号/清空会话，确认新会话不会被标记 connected，也不显示旧房间同步时间。
- **风险/遗留**：无；过期结果直接丢弃。

### B9 已修复

- **结论**：房间恢复先 await `player.restore()`，启动时本地快照与房间状态不再互相覆盖。
- **原因**：ContentView 的 `player.restore()` 与 `.coordinateListenTogether()` 的 `accountDidChange` 是两条互不等待的启动任务；restore 写回队列/repeatMode，而 `establishSession` 之后会设 `repeatMode = .all` 并清 shuffle，后完成的一方覆盖另一方。
- **改动**：`restoreSession` 在查询房间前先 await `player.restore()`，后续 ContentView 的 restore 因 `hasRestoredPlayback` 直接返回；`PlayerStore.restore()` 增加 `!isListenTogetherSessionActive` guard。
- **文件**：`MeloX/Core/Playback/Session/ListenTogetherStore.swift`、`MeloX/Core/Playback/Session/PlayerStore.swift`
- **提交**：`1ef4f65`
- **验证**：读 ContentView 141-150、ListenTogetherAppCoordination 9-13、PlayerStore 303-313/341-362、Store 424-447；静态核对，未编译。
- **手测**：房间内播放时杀 App 重启，确认队列/播放模式/暂停状态以房间为准；退出房间后仍能回到本地 repeat 与 shuffle。
- **风险/遗留**：房间恢复会等本地快照音源解析完成，启动可能稍慢；`restore()` 在 `hasRestoredPlayback` 时提前返回，可能不 await 一次进行中的 restore（残余启动竞态）。

### B0 暂缓

- **结论**：会话内单曲循环把整个房间拉回开头属产品/协议决策，未改代码。
- **原因**：NowPlayingQueuePage 会话内保留 repeat 可点；`handlePlaybackEnded` 在 `repeatMode == .one` 时 `seek(to: 0)`（默认 reportsToRoom 为 true）向房间广播 progress 0，而 repeatMode 从不随 playlist 上报（只有 displayList/randomList）。
- **改动**：未改代码；`cycleRepeatMode` 会设置 `listenTogetherPlayModeTouched`，说明会话内允许切换模式是有意设计。
- **文件**：—（报告引用 `MeloX/Features/Player/NowPlaying/NowPlayingQueuePage.swift`、`MeloX/Core/Playback/Session/PlayerStore.swift`）
- **提交**：—
- **验证**：读 NowPlayingQueuePage 241-248、PlayerStore 1000-1017/1247-1256/749-757、NeteaseListenTogetherAPI 126-138；静态核对，未编译。
- **手测**：会话内切单曲循环，曲末观察其他成员是否被拉回开头，确认产品期望后再决定是否实现房间级模式上报。
- **风险/遗留**：禁用会话内 repeat 会撤销现有行为；只抑制 `.progress` 也不完整，心跳仍会报告 progress 0。

## 5.3 b3-ipad-ui（18 条）

### E0 已修复

- **结论**：iPad 歌单/专辑详情不再把 `.system` 外观当成深色，浅色系统下整页保持浅色。
- **原因**：`resolvedPalette` 只用 `settings.appearance == .light` 判断；默认 `.system` 时走 `tabletPalette(usesLightAppearance: false)`，随后 `interfaceColorScheme`/`toolbarColorScheme` 强制整页深色。
- **改动**：两个视图各新增 `private var usesLightAppearance`，按 `(settings.appearance.preferredColorScheme ?? systemColorScheme) == .light` 解析有效外观，`resolvedPalette` 改用它。
- **文件**：`MeloX/Features/Playlist/PlaylistDetailView.swift`、`MeloX/Features/Album/AlbumDetailView.swift`
- **提交**：`36218a3`
- **验证**：读 PlaylistDetailView 299-317、AlbumDetailView 194-212、AppAppearance 32-41、MeloXApp 96-97、MusicCollectionTheme 21-47；静态核对，未编译。
- **手测**：iPad 外观"跟随系统"、系统浅色，进入任意歌单/专辑：页面、搜索框、工具栏应保持浅色；再验证系统深色与手动浅/深。
- **风险/遗留**：无；若将来详情页被放进强制 colorScheme 的子树，`systemColorScheme` 会是该子树的值。

### B3 已修复

- **结论**：iPad 宽屏页头在开启"下载全部"后不再顶掉收藏/取消收藏按钮，两者并存。
- **原因**：`MusicCollectionPrimaryActions` 用 `if let onDownloadAll { 下载菜单 } else { 收藏按钮 }` 互斥结构，iPad 宽屏页头会传非空 `onDownloadAll`。
- **改动**：始终渲染收藏 roundControl，`onDownloadAll` 存在时在同一 HStack 追加下载菜单。
- **文件**：`MeloX/Features/Playlist/PlaylistDetailContent.swift`
- **提交**：`911514d`
- **验证**：读 433-495 与 PlaylistDetailView:101；按 710pt 最小宽度估算右栏约 413pt、4 控件约 346pt 可容纳；静态核对，未编译。
- **手测**：iPad 横屏进入开启下载的歌单，页头同时出现收藏与下载；点收藏能切换；iPhone 仍只显示收藏。
- **风险/遗留**：宽页头多一个 48pt 圆钮；710pt 临界宽度仍需真机确认。

### E1 已修复

- **结论**：iPad 官方排行榜封面不再整屏宽 1:1，改为限制尺寸的宽幅封面。
- **原因**：官方排行榜在 iPad 也走 `usesToplistLayout`，`ToplistDetailHero` 封面用 `containerRelativeFrame(.horizontal)` 且 `aspectRatio` 默认 1；该分支还忽略顶部安全区。
- **改动**：`ToplistDetailHero` 增加 `usesWideLayout`：iPad 规则宽度时封面 `aspectRatio 1.55`、最大宽 420、32pt 横向边距、圆角 12、阴影、28pt 顶部间距；新增 `usesWideToplistLayout`，宽屏排行榜不再忽略顶部安全区。
- **文件**：`MeloX/Features/Playlist/PlaylistDetailContent.swift`
- **提交**：`911514d`
- **验证**：读 31-40、55-68、98-101、333-412 与 ArtworkImage 5-29、PlaylistDetailView 57-68；静态核对，未编译。
- **手测**：iPad 从 Home/搜索进入排行榜，封面约 420×271 圆角、曲目一屏内可见；iPhone 保持原全宽封面。
- **风险/遗留**：采用报告允许的"至少限制封面"替代方案（非左右分栏），且仍以 `wideArtistColumnWidth: nil` 调用 `trackContent`，排行榜曲目行仍是窄行；滚动起点从状态栏下移到导航栏下方需真机确认。

### E3 已修复

- **结论**：宽行艺人/时长补上字号层级，艺人列不再比歌名列更宽。
- **原因**：宽行艺人 `Text` 没有字体修饰（继承 body），时长也没有；艺人列宽 `(width-64)*0.39`，710pt 时约 252pt。
- **改动**：宽行艺人加 `.font(.subheadline)`，时长改 `.font(.caption.monospacedDigit())`；`MusicCollectionDetailLayout` 艺人列宽改为 `min((width - 2*musicCollectionWideInset) * 0.24, 220)`（710pt 时约 155pt）。
- **文件**：`MeloX/Features/Playlist/PlaylistTrackList.swift`、`MeloX/Features/Playlist/PlaylistDetailContent.swift`
- **提交**：`911514d`
- **验证**：读 PlaylistTrackList 141-167 与 PlaylistDetailContent 148-166，确认窄行艺人本就使用 subheadline；静态核对，未编译。
- **手测**：iPad 打开含长歌名/长艺人名的歌单，确认艺人字号小于歌名、时长更小、歌名不被挤窄。
- **风险/遗留**：长艺人名会更早截断（仍 `lineLimit(1)`）。

### E4 已修复

- **结论**：宽屏页头右栏不再锁死为封面高度，大字号下标题/副标题/元信息/按钮可完整显示。
- **原因**：右栏 VStack 用 `.frame(height: wideArtworkSize)` 固定为封面高度（约 199-215pt）；`.xxxLarge` 非辅助字号仍启用宽布局，内容可能被压缩。
- **改动**：改为 `.frame(minHeight: wideArtworkSize, alignment: .bottom)`，允许右栏随文本增高并底部对齐。
- **文件**：`MeloX/Features/Playlist/PlaylistDetailContent.swift`
- **提交**：`911514d`
- **验证**：读 141-158、249-264、299-330，确认 `.xxxLarge` 仍走宽布局；静态核对，未编译。
- **手测**：iPad 字号调到 xxxLarge 进入歌单/专辑，标题、副标题、元信息与播放按钮完整显示。
- **风险/遗留**：文本超高时页头整体变高、封面按底对齐（预期）；文本较矮时与旧布局一致。

### E5 已修复

- **结论**：浮动播放器最小宽度提高到 618pt，图标改用 Font 随 Dynamic Type 缩放，空间不足时回退紧凑播放器。
- **原因**：第一候选 `minWidth/idealWidth` 为 530，而左侧固定 240pt、右侧固定 162pt，530pt 时标题只剩约 92pt；图标字号 15/17/22/38 全部写死。
- **改动**：最小/理想宽度改为 618（240 图标 + 180 标题最小宽 + 162 操作区 + 20 间距 + 16 内边距）；`control` 参数由 size 改为 Font（随机/循环 `.footnote`、前后 `.title3`、默认 `.body`），播放键改 `.largeTitle`。
- **文件**：`MeloX/Features/Player/MiniPlayer/TabletMiniPlayerView.swift`
- **提交**：`7c961aa`
- **验证**：读文件全文、ContentView 352-355/599-609（可用宽度扣 28pt padding）与 MiniPlayerView；静态核对，未编译。
- **手测**：iPad Stage Manager 把窗口缩到 560-700pt，标题应可读或切换为紧凑播放器；调大字号检查图标比例。
- **风险/遗留**：558-618pt 窗口改用紧凑 MiniPlayerView（预期回退）；播放图标由 38pt 变为 largeTitle 默认 34pt；frame 固定，无障碍字号下该播放器本身不展示。

### E7 已修复

- **结论**：iPad 专辑宽行（`showsArtwork:false`）播放按钮的可点高度至少 44pt。
- **原因**：播放按钮 label 只有序号/标题（约 25-44pt 高），行高由右侧 42×44 菜单撑起，按钮本身没有覆盖 44pt，点行内上下留白无效。
- **改动**：在播放按钮 label 的 HStack 加 `.frame(minHeight: usesWideRows ? 44 : 0)`；非宽行不受影响。
- **文件**：`MeloX/Features/Playlist/PlaylistTrackList.swift`
- **提交**：`911514d`
- **验证**：读 95-155、257-259 与 AlbumDetailContent:44，确认菜单 42×44、行垂直 padding 为 4；静态核对，未编译。
- **手测**：iPad 专辑详情点歌名上方/下方空白应能播放；用 Accessibility Inspector 检查命中框高度。
- **风险/遗留**：宽行单行标题时 label 撑到 44pt，行高仍由菜单决定，无视觉跳变。

### E6 已修复

- **结论**：搜索分类卡白色标题增加底部 scrim，浅色渐变上对比度提高。
- **原因**：标题固定白色，但渐变含 mint/green/orange/cyan 等浅色端点，白字对比度约 2:1；未处理 Increase Contrast。
- **改动**：在颜色渐变上叠加底部黑色 scrim（35% 处透明到 100% 处 0.52，Increase Contrast 时 0.68），位于右上角装饰图标之下。
- **文件**：`MeloX/Features/Search/SearchDiscoveryView.swift`
- **提交**：`1bc0c53`
- **验证**：读 124-169 与分类颜色 183-204，按 sRGB 估算叠加后对比度约 3.3-3.8:1；静态核对，未编译。
- **手测**：浅色模式打开搜索页检查"古典/放松/电子"等卡片标题可读；开启增强对比度更明显；深色模式正常。
- **风险/遗留**：卡片下半部变暗、观感更重；装饰图标区域不受影响。

### B12 已修复

- **结论**：iPad 侧栏封面改为并发加载并一次性合并状态，不再逐张串行请求、逐张重建整页。
- **原因**：`.task(id: sidebarArtworkRequests)` 的 `loadSidebarArtwork` 用 for 循环串行 await 每张封面，每张图单独写一次 `@State sidebarArtwork`，最多 41 次串行请求与 41 次 tabs 整体重建。
- **改动**：先筛选缺失请求，用 `withTaskGroup` 并发请求 Nuke 图片（新增私有 `SidebarArtworkResult` 承载结果），本地字典收集后统一用 `UIGraphicsImageRenderer` 渲染，最后一次性 `sidebarArtwork.merge`；取消时跳过写回。
- **文件**：`MeloX/App/ContentView.swift`
- **提交**：`a4bedfa`
- **验证**：读 21-30、431-433、484-540，确认 group 内只访问 Nuke 与局部变量、渲染仍在主 actor；静态核对，未编译。
- **手测**：iPad 登录收藏超过 40 个歌单的账号冷启动，侧栏封面应更快出现，展开滚动无明显卡顿。
- **风险/遗留**：首屏最多约 41 个并发图片请求；用 `@unchecked Sendable` 包装跨任务传递的 `UIImage`，并让包含 UIKit 图像的结果字典经过 task group 边界；其实际 Sendable/隔离诊断取决于 SDK 与 Swift 编译设置——需编译确认并发安全。

### B15 已修复

- **结论**：宽行分割线右端与行内容右边缘对齐。
- **原因**：宽行 Divider trailing padding 用 `musicCollectionWideInset(32)`，而行内容 trailing padding 是 26，分割线多缩进 6pt。
- **改动**：宽行 Divider trailing 改为 26，与 `PlaylistTrackRow` 的 trailing padding 对齐。
- **文件**：`MeloX/Features/Playlist/PlaylistTrackList.swift`
- **提交**：`911514d`
- **验证**：读 38-44 与 257-258，两处常量确认；静态核对，未编译。
- **手测**：iPad 歌单列表检查分割线右端与时长/更多按钮右边缘对齐。
- **风险/遗留**：无。

### B17 已修复

- **结论**：听歌排行的周期说明从仅 accessibilityHint 改为可见 caption 文本。
- **原因**：`selectedPeriod.description` 只放在 FilterPicker 的 `accessibilityHint` 上，视觉用户看不到统计口径。
- **改动**：controls 改为外层 VStack，在 `ViewThatFits` 下方新增 caption 文本显示 `selectedPeriod.description`（`accessibilityHidden(true)`），保留原 accessibilityHint。
- **文件**：`MeloX/Features/Account/UserListeningRankView.swift`
- **提交**：`8cb0817`
- **验证**：读 114-146、225-242，确认两个说明 key 在中英文 `Localizable.strings` 均存在；静态核对，未编译。
- **手测**：打开我的听歌排行，切换本周/全部时间，picker 下方显示对应说明；VoiceOver 仍播报 hint。
- **风险/遗留**：控制区增加一行约 16pt 高度。

### E10 已修复

- **结论**：一起听期间被禁用的自动播放/自动混音按钮明显变暗。
- **原因**：两者在 Listen Together 时仅通过 `.disabled` 禁用，plain button 外观不变，视觉上仍像可点。
- **改动**：`modeButton` 增加 `.opacity(isEnabled ? 1 : 0.4)`，保留原 accessibilityHint。
- **文件**：`MeloX/Features/Player/NowPlaying/NowPlayingQueuePage.swift`
- **提交**：`9f552e7`
- **验证**：读 225-310，确认 `isEnabled` 原本只传给 `.disabled`；静态核对，未编译。
- **手测**：加入一起听后打开播放队列页，自动播放/自动混音明显变暗；退出房间恢复。
- **风险/遗留**：无，仅禁用态透明度变化。

### E12 已修复

- **结论**：宽行收藏标记改为心形并补上 VoiceOver 收藏状态。
- **原因**：宽行收藏标记用 9pt `star.fill`、固定字号且 `accessibilityHidden(true)`，`primaryActionAccessibilityValue` 不含收藏状态；同一行收藏菜单用 heart/heart.slash。
- **改动**：图标改为 `heart.fill` 加 `.font(.caption2)`；非选择模式下 `primaryActionAccessibilityValue` 用 `L10n.list` 组合"正在播放"和"已收藏"（`ui.common.favorited`）。
- **文件**：`MeloX/Features/Playlist/PlaylistTrackList.swift`
- **提交**：`911514d`
- **验证**：读 115-123、356-375、NowPlayingSongActions 47-67 与 `Localizable.strings` 的 `ui.common.favorited`（中英文均有）；静态核对，未编译。
- **手测**：iPad 歌单宽行收藏歌曲后应显示心形；VoiceOver 应播报"已收藏"。
- **风险/遗留**：心形仍只在宽行且有封面时显示（条件未改）；空数组时 `L10n.list` 返回空串。

### E13 已修复

- **结论**：浮动播放器在播客节目时直接隐藏歌词按钮，不再显示被禁用的灰按钮。
- **原因**：播客时歌词按钮只 `.disabled`，plain 按钮不变灰也无说明。
- **改动**：歌词控件改为仅在 `!song.isPodcastProgram` 时渲染；未新增本地化 key。
- **文件**：`MeloX/Features/Player/MiniPlayer/TabletMiniPlayerView.swift`
- **提交**：`7c961aa`
- **验证**：读 101-112 与 NowPlayingSongActions:17（播放页对播客隐藏收藏的既有做法）；静态核对，未编译。
- **手测**：iPad 浮动播放器播放播客时不显示歌词按钮，队列与更多可用；切回普通歌曲后恢复。
- **风险/遗留**：播客时右侧少一个按钮，标题获得更多宽度。

### E14 已修复

- **结论**：Explore 分类胶囊改用 `.controlSize(.large)`，触控高度提升到系统大号尺寸。
- **原因**：胶囊用 `.controlSize(.regular)` 的 borderedProminent 按钮，高度约 34pt，低于 44pt，且没有额外 frame/contentShape。
- **改动**：`.controlSize(.regular)` 改为 `.controlSize(.large)`。
- **文件**：`MeloX/Features/Explore/ExplorePlaylistComponents.swift`
- **提交**：`06aa68f`
- **验证**：读 8-25，确认高度来源只有 controlSize；静态核对，未编译。
- **手测**：iPhone Explore 页横向滚动分类胶囊，确认更易点中且不误触相邻项。
- **风险/遗留**：胶囊变高、字号略大，滚动区域高度增加。

### E15 暂缓

- **结论**：iPad 页面横向边距 16/32 混用属实，但统一需要新增共享 token 并改动多个页面视觉，未改代码。
- **原因**：Library 专辑网格 padding 16、详情页 `musicCollectionWideInset` 32、听歌排行 regular 32/compact 20、Home/Explore 16，缺少统一布局 token。
- **改动**：未改代码；属产品级间距决策，且本环境无法做视觉回归。
- **文件**：—（报告引用 `MeloX/Features/Library/LibraryAlbumsView.swift`、`MeloX/Features/Playlist/PlaylistDetailContent.swift`、`MeloX/Features/Account/UserListeningRankView.swift`）
- **提交**：—
- **验证**：读 LibraryAlbumsView 67-89、PlaylistDetailContent:4、UserListeningRankView 168-174，间距混用属实；静态核对，未编译。
- **手测**：真机对比 Library、详情、听歌排行的左边缘后再决定统一值。
- **风险/遗留**：只改一处会制造新的不一致；剩余工作是先定统一间距（建议 24/32 二选一）再做一次视觉回归。

### E16 已修复

- **结论**：宽页头播放按钮与圆钮图标改用相对字体，Dynamic Type 下随字号放大。
- **原因**：播放按钮硬编码 15pt 字体与 160×48 尺寸，圆钮图标固定 17pt；Dynamic Type 下标题/元信息放大而按钮不放大，固定宽度还会压缩本地化文案。
- **改动**：播放按钮字体改 `.subheadline.weight(.semibold)`、尺寸改 `minWidth 160 / minHeight 48`；圆钮图标改 `.body.weight(.semibold)`，48×48 触控尺寸保留。
- **文件**：`MeloX/Features/Playlist/PlaylistDetailContent.swift`
- **提交**：`911514d`
- **验证**：读 497-562 与调用方，确认宽布局只在非 accessibilitySize 启用；静态核对，未编译。
- **手测**：iPad 字号调到 xxxLarge 进入歌单/专辑，播放按钮文字随字号变大且不截断，圆钮比例正常。
- **风险/遗留**：长文案下胶囊可超过 160pt 宽，可能压缩同行间距；中英文案当前较短。

### E9 暂缓（有意设计）

- **结论**：侧栏歌单硬截断到 40 个是刻意设计，且"所有歌单"目录入口默认存在，未改代码。
- **原因**：`ContentView.sidebarPlaylists` 有意限制 40 个 Tab（注释：Keep the full collection in the directory instead of creating up to 2,000 tabs）；默认 `displayedSidebarLibraryTabs` 含 `.libraryPlaylists`，`showsPlaylistDirectory` 为真时插入"所有歌单"入口。
- **改动**：未改代码。
- **文件**：—（报告引用 `MeloX/App/ContentView.swift`、`MeloX/Features/Library/LibraryView.swift`）
- **提交**：—
- **验证**：读 ContentView 373-399、436-448、450-476，LibraryView 28-30，AppSettings 533-538，确认上限是设计取舍且目录入口默认存在；静态核对，未编译。
- **手测**：（可选）iPad 登录超过 40 个收藏歌单的账号，确认默认侧栏有"所有歌单"入口且完整列表可达。
- **风险/遗留**：只有用户主动分离/关闭该页时侧栏才没有入口，此时页面仍以独立 Tab 或 Library 页面可达。

## 5.4 b4-perf-hot（10 条）

### C1 已修复

- **结论**：100ms 时钟回调不再每 tick 跑完整派生更新，改为签名去重 + 节流。
- **原因**：`handlePlaybackClockSample` 每 100ms 无条件调 `updateNowPlayingLyricMetadata`/`updateLyricsLiveActivity`/`updateLyricsNotification`/`persistSnapshot`/`prepareAutoMixIfNeeded`，每次都重算 `LyricPlaybackTimeline.position`（O(歌词数)）、做 L10n/字符串格式化，Live Activity 还要 CoreText 量宽，每秒编码整个队列。
- **改动**：新增文件级 `PlaybackDerivedStateSignature(songID, highlightedLyricID, isPlaying, seekRevision)` 与 `updatePlaybackDerivedStateIfNeeded()`：每 tick 只做一次时间线定位，签名变化时才更新 Now Playing 歌词/通知，Live Activity 签名变化立即刷新、其余每 0.25s 刷新一次；`prepareAutoMixIfNeeded()` 增加 `isAutoMixEnabled/isPlaying/repeatMode` 前置 guard。
- **文件**：`MeloX/Core/Playback/Session/PlayerStore.swift`
- **提交**：`be0fcb7`
- **验证**：读 AudioPlaybackEngine 83-93 与旧 handler 1428-1449，确认三个函数在去重前都会重算 position；确认 seek/updateNowPlayingState 等强制路径仍直接调用；静态核对，未编译。
- **手测**：播放时观察锁屏/灵动岛歌词换行是否及时；长句紧凑歌词是否仍完整滚动；暂停、恢复、拖动后 Now Playing 歌词与通知是否正确更新。
- **风险/遗留**：Live Activity 紧凑滚动由每 tick 改为最多 4Hz 且经 8pt 量化，观感可能略粗；C1 依赖可选三元与类型推断（`?:`），未编译。

### A9 已修复

- **结论**：进度改为独立标量键、最多每 5 秒写一次，不再每秒编码整队列 JSON。
- **原因**：tick 每秒调 `persistSnapshot()`，`JSONEncoder` 编码完整 `[Song]` 队列并写 UserDefaults；`PlaybackPersistence.save` 用 `try?` 静默吞掉编码失败。
- **改动**：新增独立键 `player.playbackProgress` 与 `saveProgress(_:)`；tick 最多每 5 秒（`playbackProgressPersistInterval`）只写进度标量，`persistSnapshot()` 保留给切歌/暂停/seek/队列变化并在其后记录时间戳；`load()` 用进度键覆盖快照进度；`clear()` 清两个键；编码/解码失败改用 OSLog。
- **文件**：`MeloX/Core/Playback/Session/PlayerStore.swift`、`MeloX/Core/Playback/Queue/PlaybackPersistence.swift`
- **提交**：`be0fcb7`
- **验证**：读旧 PlayerStore 1443-1447 与旧 PlaybackPersistence 30-42，确认结构性改动仍走 `persistSnapshot → save()`、`restore()` 仍从 `load()` 取进度；静态核对，未编译。
- **手测**：播放中后台杀 App 再启动，续播误差应不超过约 5 秒；手动暂停后杀 App 应精确保留；清空队列后重启不应恢复旧队列。
- **风险/遗留**：强杀最多丢约 5 秒续播位置；旧安装无进度键时回退到快照进度；`PlaybackPersistence` 仅 iOS target，MeloXDesktop 同名副本未改。

### C4 已修复

- **结论**：时长未变化时不再每 100ms 重发 duration、也不再重写 Now Playing。
- **原因**：AudioPlaybackEngine 每 100ms 调 `publishDurationIfAvailable()`，即使时长未变也触发 `onDurationChanged`；PlayerStore 每次赋值 `duration`（@Observable 失效）并调 `updateNowPlayingState()` 写 MPNowPlayingInfoCenter。
- **改动**：引擎新增 `publishedDuration` 缓存，仅时长变化 ≥ 0.1s 才回调；`load()`/`unload()`/AutoMix 切换完成时清空缓存；PlayerStore 的 `onDurationChanged` 增加 `self.duration != value` 守卫。
- **文件**：`MeloX/Core/Playback/Engine/AudioPlaybackEngine.swift`、`MeloX/Core/Playback/Session/PlayerStore.swift`
- **提交**：`be0fcb7`
- **验证**：读 AudioPlaybackEngine 83-93、230-231 与 PlayerStore `bindEngine`，确认 load 与 AutoMix 完成都会重置缓存；静态核对，未编译。
- **手测**：锁屏 Now Playing 时长与进度条正确；连续切换不同时长的歌曲，时长能正确变化。
- **风险/遗留**：0.1s 内的细微时长修正不再推送（不可感知）；换曲路径已重置缓存，不会漏更新。

### C2 已修复

- **结论**：Live Activity 发布签名对紧凑滚动距离做 8pt 量化，实际更新最多约 4Hz。
- **原因**：`LyricsLiveActivityPublicationSignature` 包含随进度连续变化的 `compactScrollDistancePoints`，签名几乎每 tick 都不相等，ActivityKit 被高频 update。
- **改动**：紧凑滚动距离按 8pt 步长量化（`Int((distance/8).rounded())*8`），快照仍带精确距离；结合 C1 的 0.25s 节奏，`activity.update` 最多约 4Hz 且只在越过量化步长时发生。
- **文件**：`MeloX/Core/Playback/Session/PlayerStore.swift`
- **提交**：`be0fcb7`
- **验证**：读 `updateLyricsLiveActivity` 与 `LyricsLiveActivityController` 的去重/合并逻辑，确认签名只用于去重、ContentState 仍带真实距离与 playbackPosition/updatedAt；静态核对，未编译。
- **手测**：播放长句歌词观察灵动岛紧凑歌词滚动是否流畅、句尾是否完整；换行是否立即切换。
- **风险/遗留**：滚动目标最多滞后约 8pt/0.25s；widget 自带 `.linear(0.55)` 可平滑，极端情况下观感略跳。

### C22 已修复

- **结论**：进度区拆成叶子视图，容器 body 不再每 100ms 读取 progress 重建整块视图树。
- **原因**：`NowPlayingProgressControl.body` 直接读 `player.progress`（Slider binding、两处时间 Text、无障碍 value），每 100ms 重建含 AutoMix 状态与音质菜单的整棵树，并多次执行 `L10n.format/String(format:)`。
- **改动**：拆出叶子视图 `NowPlayingProgressSlider`（Slider 与无障碍值）与 `NowPlayingProgressTimeRow`（已播放/剩余时间），容器只读 duration 与 `isAutoMixTransitioning`；`formatTime` 提到文件级 `formatPlaybackTime`。
- **文件**：`MeloX/Features/Player/NowPlaying/NowPlayingControls.swift`
- **提交**：`6242a88`
- **验证**：读原 body 4-64 与改后结构，确认布局修饰符、overlay 结构与坐标未变；grep 确认 `formatPlaybackTime` 唯一、容器未读 progress；静态核对，未编译。
- **手测**：播放时进度条与时间正常；AutoMix 状态与音质菜单不再随进度刷新；开 VoiceOver 读取进度值正确。
- **风险/遗留**：无障碍值仍在 Slider 叶视图随进度计算（保证数值准确），但重建范围已缩小。

### A13 暂缓

- **结论**：下载库在主线程同步写 GRDB / VACUUM / 打开数据库的问题仍在，未改代码。
- **原因**：`DownloadStore` 为 `@MainActor`，`recordPlayback` 同步执行 GRDB 写入，`clearPlaybackCounts/optimizeStorage` 在主线程执行 VACUUM，init 在主线程打开数据库并逐条检查文件。
- **改动**：未改代码；修复需要把 `DownloadDatabase` 改为 nonisolated/后台 actor，并把 `recordPlayback`、`clearPlaybackCounts`、`optimizeStorage` 及初始化改为异步，涉及多处 @Observable 状态与缓存判定顺序，无编译器无法保证安全。
- **文件**：—（报告引用 `MeloX/Core/Downloads/DownloadStore.swift`、`MeloX/Core/Downloads/DownloadDatabase.swift`）
- **提交**：—
- **验证**：读 DownloadStore 181-199、312-336 与 DownloadDatabase 29-99；静态核对，未编译。
- **手测**：建议后续单独批次处理，并用 Instruments 测播放/清理时的主线程占用。
- **风险/遗留**：问题仍在；剩余工作是把数据库层后台化并重排 @Observable 状态更新。

### C0 暂缓

- **结论**：歌词解析仍在主线程同步执行，未改代码。
- **原因**：`LyricsService` 为 `@MainActor`，网络返回后在主线程同步执行 `LyricSourceMerger.resolve → TTMLLyricParser/LyricParser` 解析。
- **改动**：未改代码；工程设置 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，`LyricSourceMerger`/解析器/TTML 文档与节点/`LyricLine` 整条链路均为隐式 MainActor，放进 `Task.detached` 需逐类型标 nonisolated 并核对 Sendable，属跨多文件重构。
- **文件**：—（报告引用 `MeloX/Core/Lyrics/LyricsService.swift`、`MeloX/Core/Lyrics/LyricSourceMerger.swift`）
- **提交**：—
- **验证**：读 LyricsService、LyricSourceMerger 与解析链，确认隐式 MainActor 链路；静态核对，未编译。
- **手测**：建议后续单独批次处理，并实测长歌词切歌耗时。
- **风险/遗留**：解析仍在主线程；剩余工作是隔离改造 + 真机耗材测量。

### C3 暂缓（部分已修复）

- **结论**：只把 Apple Music 背景帧率从 120fps 降到 60fps，`maxSampleOffset` 与 `drawingGroup` 未改。
- **原因**：歌词页背景在 ProMotion 上以 120Hz 每帧执行两次全屏 Metal `layerEffect`，中间夹 80pt 高斯模糊，GPU 成本高。
- **改动**：`TimelineView` 的 `minimumInterval` 从 1/120 下调到 1/60，ProMotion 全屏着色器工作量减半；报告明确说明缩小采样偏移会引入边缘错误、`drawingGroup` 与 `layerEffect` 组合可能改变合成结果，故未改。
- **文件**：`MeloX/Features/Player/NowPlaying/AppleMusicBackdrop/NowPlayingAppleMusicBackground.swift`
- **提交**：`8edce1a`
- **验证**：读背景视图与 `AppleMusicBackdropShaders.metal`，确认 rotation 着色器按 `modelScale 0.7` 采样、偏移可达整屏；静态核对，未编译。
- **手测**：歌词页背景旋转与音频响应是否仍流畅；对比发热与掉帧；确认画面无边缘异常。
- **风险/遗留**：120Hz 设备上背景由 120fps 降到 60fps，慢速旋转模糊背景基本无差异；剩余工作是在真机上评估 `maxSampleOffset` 与 `drawingGroup`。

### C6 已修复

- **结论**：歌词高亮同步删除 `onChange(of: player.progress)`，只保留精确 sleep 的 `.task(id:)`。
- **原因**：同时使用 `.onChange(of: player.progress)` 和 `.task(id: synchronizationTrigger)` 精确 sleep 到换行点，前者每 100ms 触发一次 O(歌词数) 的 `LyricPlaybackTimeline.position`。
- **改动**：删除 progress 的 onChange 与仅供它使用的 `synchronizeImmediately()`，只保留 `.task(id:)`（出现时立即同步，并随 songID/seekRevision/isPlaying/advanceTime/歌词标识变化重启）。
- **文件**：`MeloX/Features/Player/NowPlaying/NowPlayingLyricSynchronizer.swift`
- **提交**：`aa3b4c5`
- **验证**：读改后文件与 `LyricSynchronizationTrigger`，确认 task 首次运行即调用 `updateHighlightedLyric`，seekRevision/isPlaying/歌词变化都在触发键内；静态核对，未编译。
- **手测**：歌词页高亮随播放、拖动进度、暂停恢复正确；切换歌词源后高亮正确。
- **风险/遗留**：若 progress 在 seekRevision 不变的情况下被外部直接改写，高亮会延后到下一个边界唤醒（一起听同步路径同时会 updateNowPlayingState，影响较小）；触发键依赖歌词标识，若中段时长/来源变化而端点 ID 不变，可能失去周期兜底。

### C13 已修复

- **结论**：间奏视图同 C6，删除 progress 的 10Hz onChange，只保留 `.task(id:)`。
- **原因**：`AppleMusicLyricsFocusCoordinator`（同文件内）既有 `.onChange(of: player.progress)` 又有 `.task(id: synchronizationTrigger)`，每个 tick 额外做一次 `LyricPlaybackTimeline.position` + `LyricInterludeTimeline.position`。
- **改动**：删除 progress 的 onChange，保留 `.onChange(of: isActive)` 与 `.task(id:)`；触发键已包含 isActive/seekRevision/isPlaying/歌词与间奏标识。
- **文件**：`MeloX/Features/Player/Lyrics/AppleMusic/AppleMusicLyricInterludeView.swift`
- **提交**：`aa3b4c5`
- **验证**：读该文件与 `AppleMusicLyricsFocusSynchronizationTrigger`，确认 task 在出现和触发键变化时立即执行 `synchronizeAtTransitions`；静态核对，未编译。
- **手测**：歌词页高亮与间奏点动画在播放/拖动/暂停时正常，切换间奏模式后同步正确。
- **风险/遗留**：与 C6 相同的边界情况（progress 无 seekRevision 变化地跳变时高亮延后到下一唤醒）。

## 5.5 b5-downloads-network（14 条）

### A1 已修复

- **结论**：单条坏记录不再让整个下载库不可用，改为跳过并记录日志。
- **原因**：`fetchDownloads()` 在 `databaseQueue.read` 内对全部记录 `.map { try $0.downloadedSong() }`，任意一行 quality 非法或 songJSON 解码失败都会让整个查询抛错，`DownloadStore.init` 捕获后 `resolvedDatabase` 为 nil，后续操作全部 unavailable。
- **改动**：`fetchDownloads()` 改为先 `fetchAll`，再 `compactMap` 加逐行 do/catch；坏行用 Logger 记录 songID 与错误后跳过，只有数据库本身读取失败才抛出。
- **文件**：`MeloX/Core/Downloads/DownloadDatabase.swift`
- **提交**：`156a008`
- **验证**：读原 29-35 与 DownloadStore init 84-110，确认 `downloadedSong()` 的 `MusicQuality(rawValue:)` 与 JSONDecoder 都可能抛错、方法签名与调用方未变；静态核对，未编译。
- **手测**：向 downloads 表插入 quality 非法或 songJSON 损坏的记录后启动，下载页应仍显示其余歌曲并可播放/删除，Console 出现 Skipping corrupt download record。
- **风险/遗留**：坏记录被跳过（仅日志），对应音频成为未跟踪文件，可被 repairStorage 清理，但不会自动删除坏行。

### A2 已修复

- **结论**：下载安装前增加内容校验，200 HTML/JSON 错误页或截断文件不再被永久入库。
- **原因**：`DownloadStore.download` 在安装前只校验 HTTP 2xx 和空文件，CDN/WAF 返回的 200 HTML/JSON 错误页或截断文件会被永久写入并入库，之后 `start()` 因 `contains(songID:)` 拒绝重下、`repairStorage` 也因文件存在不清理。
- **改动**：新增 `validateDownloadedFile(at:response:)`：拒绝 `text/*`、JSON/XML MIME；要求非空且实际字节数不小于 Content-Length（若提供）；用 `hasAudioFileSignature` 校验 ID3/FLAC/Ogg/RIFF/APE/Matroska/ASF/MP4 ftyp/MPEG-ADTS 魔数；在 `installDownloadedFile` 之前调用，失败由已有 defer 删除临时文件。
- **文件**：`MeloX/Core/Downloads/DownloadStore.swift`
- **提交**：`fa7c3a7`
- **验证**：读原 372-386、`DownloadStorage.installDownloadedFile` 与调用方 defer；魔数覆盖当前 MusicQuality 可能返回的 mp3/flac/aac/m4a 容器；静态核对，未编译。
- **手测**：用代理把下载 URL 改写成 200 HTML 或截断音频，下载应报无效响应且下载库不新增记录；正常 mp3/flac/aac 下载应成功。
- **风险/遗留**：合法音频若是非常规容器或带前导垃圾字节可能被误判；MIME 只拒绝明显错误类型；Content-Length 仅在实际更小时拒绝（避免压缩传输误伤）。

### A3 已修复

- **结论**：重新下载改为原子替换，失败不再同时丢旧文件和新文件。
- **原因**：`installDownloadedFile` 先删除同名目标文件再 move 临时文件；move 失败或随后 size 校验失败会两份都丢。
- **改动**：先在临时文件上读取并校验 `fileSize`（空文件只删临时文件、保留旧文件）；目标存在时用 `FileManager.replaceItemAt` 原子替换，不存在时才 move；`replaceItemAt` 失败会保留旧文件，临时文件由调用方 defer 清理。
- **文件**：`MeloX/Core/Downloads/DownloadStorage.swift`
- **提交**：`94275bc`
- **验证**：读原 27-39 与 `DownloadStore.download` 的 defer，确认覆盖时文件名稳定命中同一 URL、`replaceItemAt` 为 Foundation 原子替换 API（部署目标 26.0）；静态核对，未编译。
- **手测**：重复下载同一首歌并在磁盘满或临时文件被删时触发失败，旧下载应仍可播放；正常重复下载应成功替换且不残留临时文件。
- **风险/遗留**：替换瞬间可能短暂占用额外磁盘；旧文件权限/文件保护导致替换失败时行为变为保留旧文件并报错（符合预期）。

### A23 已修复

- **结论**：启动时清理孤儿暂存文件，进程中断后不再永久残留下载临时文件。
- **原因**：`didFinishDownloadingTo` 把文件移到 `MeloXDownloadTransfers`，只有 `didCompleteWithError` 的 error 分支删除；进程在两者之间被杀会永久残留，而 StorageMaintenance 在有活动下载时会保留该目录。
- **改动**：`DownloadTransferClient.init` 中调用 `removeOrphanedStagedFiles()`，启动时清空 `AppStorageLocations.downloadTransferDirectory()` 下所有暂存文件，删除失败记录日志。
- **文件**：`MeloX/Core/Downloads/DownloadTransferClient.swift`
- **提交**：`0114bec`
- **验证**：读原 83-100/109-111 与 MeloXApp:34（只创建一个 DownloadStore/DownloadTransferClient）；静态核对，未编译。
- **手测**：下载大文件过程中从多任务界面强杀 App，重启后检查 `tmp/MeloXDownloadTransfers` 为空；随后正常下载不受影响。
- **风险/遗留**：若同一进程创建第二个 client 且第一个仍有活动传输，会删除其暂存文件；当前 App 只有一个实例，风险可忽略。

### A15 已修复

- **结论**："清理临时文件"不再删除歌词通知附件目录。
- **原因**：`clearTemporaryFiles` 无条件把 `LyricsNotificationAttachments` 加入删除候选，而该目录由 `LyricsNotificationAttachmentStager` 写入并负责 1 小时/最多 8 个文件的清理策略。
- **改动**：从 `clearTemporaryFiles` 的 candidates 中移除 `lyricsNotificationAttachmentDirectory`；`measuredDiskUsage` 仍统计其占用。
- **文件**：`MeloX/Core/Storage/StorageMaintenance.swift`
- **提交**：`bd3cac0`
- **验证**：读原 72-80、stager 的 `stage/cleanStagedAttachments` 与 `StorageManagementModel` 调用点；静态核对，未编译。
- **手测**：先触发一条带封面的歌词通知，再执行设置里的清理临时文件，已排队/已显示通知的附件不应被删；多次通知后旧附件仍按 stager 策略清理。
- **风险/遗留**：清理临时文件可回收字节略少，但目录会在下次通知 staging 时自行清理。

### A10 已修复

- **结论**：未登录时不再把超时/DNS/5xx/noPlayable 全部伪装成外链播放源。
- **原因**：`playbackSource` 的外层 catch-all 把所有非取消错误转换成未登录外链 `PlaybackSource`，`PlayerStore` 误以为解析成功，真实错误被吞掉。
- **改动**：外层 catch 先识别 `Task.isCancelled`/`URLError.cancelled` 并抛 `CancellationError`；仅当错误是 `APIError.noPlayableSource` 且未登录时才返回 `music.163.com/song/media/outer/url`，其余错误原样抛出。
- **文件**：`MeloX/Core/Networking/NeteaseAPI.swift`
- **提交**：`851581a`
- **验证**：读 383-420 与原 `requestPlaybackSource` 抛错路径，确认 PlayerStore 的失败/重试逻辑能看到真实错误；静态核对，未编译。
- **手测**：飞行模式下未登录播放一首歌，应快速显示网络错误而不是 00:00；正常无版权歌曲仍走外链兜底；取消播放不应再发起第二次请求。
- **风险/遗留**：未登录遇到服务端 5xx 将直接报错而不是尝试外链（报告期望行为）；版权类 server 错误不再伪装成成功。

### A12 误报

- **结论**：复核后确认是误报：scope 在 async actor 调用/await 之前已按当前 cookie 求值，不存在"await 之后取 cookie 计算 scope"的路径。
- **原因**：`await storage.store(data, scope: Self.scope(for: settings.cookie), key: key)` 中 Swift 在调用异步函数前先求值实参，scope 在 actor hop 前固定；三个调用方（`LibraryStore.persistContent`、`HomeRecommendedView.persistContent`、`PlaylistDetailView.persistContent`）都在 await 后用当前 cookie 与请求开始时的 token 做 guard 后才调用 store。
- **改动**：未改代码。
- **文件**：—（报告引用 `MeloX/Core/Storage/PageContentCache.swift` 及三个调用方）
- **提交**：—
- **验证**：读 PageContentCache 14-29、LibraryStore 797-819、HomeRecommendedView 360-370、PlaylistDetailView 636-642；静态核对，未编译。
- **手测**：无需；如仍担心，可在切号时观察 PageContent 缓存 scope，当前实现已按调用时 cookie 定 scope。
- **风险/遗留**：无。

### A24 已修复

- **结论**：网络取消不再被当成失败并再发一次 account/get 请求。
- **原因**：`accountProfile` 只捕获 `CancellationError`，而 URLSession 取消通常抛 `URLError(.cancelled)`；同时任意 5xx/超时都会进入 catch 并再请求 `/api/nuser/account/get`。
- **改动**：catch 中先判断 `Task.isCancelled`/`URLError.cancelled` 并抛 `CancellationError`；仅对 `APIError.notLoggedIn` 和 `APIError.emptyResponse` 走旧接口兜底，其余错误原样抛出。
- **文件**：`MeloX/Core/Networking/NeteaseAPI.swift`
- **提交**：`851581a`
- **验证**：读 624-648 与 `NeteaseDirectClient.decode`（非 2xx→server、空 body→emptyResponse），确认不再对网络/服务端错误发第二次请求；静态核对，未编译。
- **手测**：切号/退出登录时抓包，应只看到一次 account/get 请求；正常空 profile 账号仍能通过旧接口取到资料。
- **风险/遗留**：若首接口因其他可恢复 `APIError`（如 invalidResponse）而旧接口本可成功，现在会直接失败（报告建议只在空 profile/emptyResponse 回退）。

### A25 已修复

- **结论**：云盘刷新返回后复核 cookie，切号时旧账号数据不再写入新账号界面。
- **原因**：`refresh` 在 `await api.cloudSongs` 后只用 `Task.checkCancellation()`，未复核捕获的 cookie；切号时旧请求成功返回会把旧账号列表/配额写入新账号并记 `loadedCookie` 为旧值。
- **改动**：await 后新增 `guard settings.cookie.trimmingCharacters(in: .whitespacesAndNewlines) == cookie else { return }`，不匹配直接丢弃结果。
- **文件**：`MeloX/Core/Cloud/CloudMusicStore.swift`
- **提交**：`ff03f6a`
- **验证**：读 55-102 与 `LibraryStore.isCurrentRefresh` 模式，确认 `refreshingCookie` 的 defer 只清理对应 cookie、`CloudMusicView` 有 `.task(id: settings.cookie)` 触发新刷新；静态核对，未编译。
- **手测**：两个账号快速切换并进入云盘页，旧账号列表/配额不应出现；新账号刷新完成后显示正确数据。
- **风险/遗留**：切号瞬间旧请求被丢弃后 phase 可能短暂停在 loading，等新账号 refresh 触发后恢复。

### A20 已修复

- **结论**：流媒体预加载失败后 AutoMix 会在后续 tick 重新规划，不再对同一对歌曲永久放弃。
- **原因**：`handlePreparationFailure` 只在 `context.sourceIsDownloaded` 为真时重置 attempt；流媒体失败时 `preparedContext` 置 nil 但 attempt 保留，`prepareIfNeeded` 的 `attempt != nextAttempt` guard 阻止同一对歌曲再次规划。
- **改动**：在下载/流媒体分支之前统一 `attempt = nil`，让下一次时钟 tick 重新规划；下载源失败仍调用 `discardInvalidDownload`。
- **文件**：`MeloX/Core/Playback/AutoMix/AutoMixPlaybackCoordinator.swift`
- **提交**：`4556bcc`
- **验证**：读 109-114、`prepareDeckIfNeeded` 与 `handlePreparationFailure` 374-393，确认失败回调只在 `preparedContext` 匹配时触发、重置后任务 defer 会清空引用；静态核对，未编译。
- **手测**：弱网下播放到 AutoMix 预加载点让流媒体解析失败一次，恢复网络后同一对歌曲应能在后续 tick 重新准备；下载歌曲失败仍应从下载库清除。
- **风险/遗留**：持久性失败会在后续 tick 反复重试（报告允许），可能增加网络请求；未见额外退避闸门，需真机观察是否形成重试风暴。

### A11 暂缓

- **结论**：API 加解密与 JSON 解码仍在主线程执行，未改代码。
- **原因**：`NeteaseAPI` 与 `NeteaseDirectClient` 均为 `@MainActor`，weapi/eapi 的 AES/RSA/MD5 与 `JSONDecoder` 都在主线程执行。
- **改动**：未改代码；移出主线程需要让 client 跨 actor 访问 `AppSettings`（cookie/quality）或持续同步设置，并重新审查所有调用方隔离，无编译器无法保证。
- **文件**：—（报告引用 `MeloX/Core/Networking/NeteaseAPI.swift`、`MeloX/Core/Networking/NeteaseDirectClient.swift`）
- **提交**：—
- **验证**：读 NeteaseAPI 51-53、NeteaseDirectClient 6-7/179-239；静态核对，未编译。
- **手测**：建议后续单独批次，并用 Instruments 测大歌单/分页解析的主线程耗时。
- **风险/遗留**：主线程开销仍在；剩余工作是隔离改造 + 设置读取方案。

### D15 暂缓（部分已修复）

- **结论**：首页兜底加载的失败已能记录日志，但仍无 UI 错误通道、也不保留上次缓存。
- **原因**：`HomeRecommendationFallbackLoader` 的 7 处 `try?` 把未登录、网络失败、服务端错误和真实空内容都折叠成 `[]`，没有任何日志或错误通道。
- **改动**：引入 OSLog logger 与 `logFailure(endpoint:error:)`（跳过取消），7 处 `try? ... ?? []` 改为 do/catch 并记录 endpoint 与错误；返回值仍为 `[]`，UI 行为未变。
- **文件**：`MeloX/Features/Home/HomeRecommendationFallbackLoader.swift`
- **提交**：`7329c02`
- **验证**：读全部 7 个 fallback 方法 79-219 与调用方 `HomeRecommendedView.loadFallbacks`；静态核对，未编译。
- **手测**：断网进入首页或关闭对应 feature，Console 过滤 category HomeRecommendations 应看到具体 endpoint 失败；正常有内容时无错误日志。
- **风险/遗留**：仅新增日志；UI 仍未区分无内容/失败，失败时也未保留上次缓存。剩余工作：错误状态上报 + 上次成功结果缓存。

### D20 已修复

- **结论**：PageContentCache 打开/读写失败不再静默，改为 OSLog 记录并一次性上报。
- **原因**：`PageContentCacheStorage` 打不开数据库时静默 `database=nil`，之后所有读写用 `try?` 吞掉错误，缓存永远 miss 且无日志。
- **改动**：引入 OSLog logger；init catch 记录打开失败；`data/store/remove/removeAll/vacuum` 改为显式 do/catch，首次失败通过 `report(_:operation:)` 记录一次（`hasReportedFailure` 去重）。
- **文件**：`MeloX/Core/Storage/PageContentCache.swift`
- **提交**：`4fe619b`
- **验证**：读原 47-110 与 GRDB `DatabaseQueue` 的 read/write/vacuum 调用，确认 public API 与 256 条淘汰逻辑未变；静态核对，未编译。
- **手测**：将 PageContent 目录设为不可写或损坏 `content.sqlite` 后启动，Console 应出现 Failed to open page content cache 或读写失败日志；正常缓存命中不受影响。
- **风险/遗留**：仅增加日志与一次性上报；读写失败仍返回 nil/忽略，不会让上层崩溃。

### D21 已修复

- **结论**：手选的 QQ 歌词匹配从 Caches 迁移到 Application Support，写入改为显式错误处理。
- **原因**：`Caches/MeloX/Lyrics/qq-matches.json` 可被系统随时清理；`createDirectory/write` 全用 `try?`，读取失败直接置空 matches，无法与尚无匹配区分。
- **改动**：默认路径改为 `AppStorageLocations.applicationSupportRoot()/Lyrics/qq-matches.json`；启动时若新路径不存在且旧 Caches 文件存在则 move 迁移；load/persist 改为显式 do/catch，atomic 写失败保留旧文件。
- **文件**：`MeloX/Core/Lyrics/QQMusicLyricMatchStore.swift`
- **提交**：`d2b1412`
- **验证**：读原 49-70 与调用点 `QQMusicLyricsClient:9`（默认构造、无自定义 URL），确认 `applicationSupportRoot()` 已存在、迁移只在默认路径分支执行；静态核对，未编译。
- **手测**：升级安装后播放一首手动纠正过歌词的歌，匹配应保留；清掉 Caches 后手动选择 QQ 匹配，重启仍在；Console 无迁移/持久化错误。
- **风险/遗留**：迁移 `moveItem` 失败时旧文件留在 Caches 并记录日志、下次启动重试；首次启动若无旧文件则创建空目录；`QQMusicLyricMatchStore` 的 actor/static 隔离需编译确认。

## 5.6 b6-perf-views（21 条）

### C5 暂缓

- **结论**：每行最多 3 条 TimelineView 同时刷新的问题仍在，未改代码。
- **原因**：`SynchronizedLyricText.swift:376-390` 与 `470-500` 各挂一条 TimelineView，`AppleMusicLyricsView.swift:566` 的 `LyricRowPresentationTimeline` 再叠加一条；焦点/换行动画期间非主唱行 `playbackFocusProgress > 0`，三条时间线都按 `effectiveLyricsRefreshRate` 每帧求值并重建 Text/textRenderer。
- **改动**：未改代码；合并 ruby 与主文字时间线需要把单一 clock 下传到所有 `SynchronizedLyricText` 调用点，涉及多文件与大量视觉时序，无编译环境无法安全完成。
- **文件**：—（报告引用 `MeloX/Features/Player/Lyrics/Shared/SynchronizedLyricText.swift`、`MeloX/Features/Player/Lyrics/AppleMusic/AppleMusicLyricsView.swift`）
- **提交**：—
- **验证**：读两处 TimelineView、`LyricRowPresentationTimeline` 的 paused 条件与 AppleMusicLyricsView 594-644；静态核对，未编译。
- **手测**：高刷设备播放歌词，用 Instruments 观察换行/焦点动画期间各 TimelineView 闭包调用次数。
- **风险/遗留**：属结构性重构，需要先合并时间线再验证视觉时序。

### C7 暂缓（部分已修复）

- **结论**：`position()` 的 filter+map+Set 已合并为一次遍历，但仍保留前缀遍历，精确歌词的全量重叠检查未变。
- **原因**：`position(at:in:)` 二分得到 lowerBound 后仍对 `0..<lowerBound` 做 filter 生成数组再 map 建 Set；结果为空时还用 `last(where:)` 再扫一遍前缀；该函数被 PlayerStore、通知、悬浮歌词以约 10Hz 调用。
- **改动**：filter+map+Set 合并为一次遍历：命中时同时 append 到 `activeLyrics` 并 insert 到 `activeLyricIDs`；空结果回退直接复用 `lowerBound-1` 的 `latestStartedLine`，去掉额外前缀扫描；前缀遍历仍保留（精确歌词需检查所有可能重叠行）。
- **文件**：`MeloX/Core/Lyrics/LyricPlaybackTimeline.swift`
- **提交**：`640740f`
- **验证**：读 PlayerStore 1485/1624/1668、LyricsNotificationPublication:123、FloatingLyricsController:368 等调用方，逐分支比对新的 if/else 与原 filter 的 precise/lineSynchronized 语义；静态核对，未编译。
- **手测**：长歌词后段拖动进度并播放，确认对唱/重叠行高亮与之前一致，Instruments 观察 10Hz 路径分配下降。
- **风险/遗留**：低；仍沿用"lyrics 按 time 升序"的二分假设；剩余工作是进一步降低前缀扫描成本（例如按行缓存可重叠集合）。

### C8 已修复

- **结论**：透明 retained 行不再保留完整时间线动画，隐藏副本停止逐帧求值。
- **原因**：`lyricRow` 对 `retainedCascadeLyrics` 中的行仍传 `isActive: isActive`，`SynchronizedLyricText` 的 `isAnimationActive` 也是 `isActive`；这些行同时被 `opacity(0)` 隐藏、又在 retained overlay 里再渲染一份。
- **改动**：`lyricRow` 内改为 `isActive: isActive && !isRetainedCascadeLine`，`isAnimationActive` 同步改成 `isActive && !isRetainedCascadeLine`；overlay 中可见的 retained 副本保持原逻辑。
- **文件**：`MeloX/Features/Player/Lyrics/AppleMusic/AppleMusicLyricsView.swift`
- **提交**：`350c745`
- **验证**：读 545 的 `isRetainedCascadeLine` 定义、566-571/594-598 改点与 1203 的 overlay 副本，确认两处参数只影响 LazyVStack 中的隐藏副本；静态核对，未编译。
- **手测**：播放快速换行歌曲，确认 retained 行的淡出/位移仍由 overlay 正常显示且无闪烁。
- **风险/遗留**：低；隐藏副本本来 `opacity 0`，不参与可见动画。

### C9 暂缓

- **结论**：body 每次求值重算 `interludes`/`displayItems` 全量数组的问题仍在，未改代码。
- **原因**：`interludes`、`interludeByID`、`displayItems` 都是计算属性，`displayItems` 内部还会再次调用 `interludes`；body 的 focus coordinator（173 行）与 ForEach（454 行）各触发一次，高亮与 `lyricLayoutRevision` 变化都会让 body 重算，长歌词时每次 O(n) 分配与字典构建。
- **改动**：未改；缓存需要在 lyrics 与 settings 的间奏策略变化时维护 State，并同步 `visibleInterlude/retainedInterlude` 的失效逻辑，属结构性改动。
- **文件**：—（报告引用 `MeloX/Features/Player/Lyrics/AppleMusic/AppleMusicLyricsView.swift`）
- **提交**：—
- **验证**：读 1409-1433 与 173/454/2300 的使用点，确认重复计算真实存在；静态核对，未编译。
- **手测**：长歌词加间奏场景，用 Instruments 观察每次换行时 displayItems/interludes 构建次数。
- **风险/遗留**：需要引入派生数据缓存并定义失效条件。

### C10 暂缓

- **结论**：任意行注解高度变化触发整棵歌词视图重建的问题仍在，未改代码。
- **原因**：`AppleMusicLyricsGeometryCache` 是 `@MainActor final class` 并刻意放在 Observation 之外（滚动几何不应让整个歌词视图失效），因此修改 `annotationHeights/layoutHeights` 不会自动触发 body，242 行读取 `lyricLayoutRevision` 是唯一失效手段。
- **改动**：未改；直接删除 revision 读取会让注释高度和几何变化后的焦点位置/偏移不再更新；报告建议的按 id 拆 Equatable 子视图属大规模重构。
- **文件**：—（报告引用 `MeloX/Features/Player/Lyrics/AppleMusic/AppleMusicLyricsGeometryCache.swift`、`MeloX/Features/Player/Lyrics/AppleMusic/AppleMusicLyricsView.swift`）
- **提交**：—
- **验证**：读 cache 3-11（class 且不参与 Observation）与 view 242/1669/1690/1724，确认 revision 是唯一 body 失效路径；静态核对，未编译。
- **手测**：切换翻译/罗马音显示，确认行高与焦点位置更新正常；拆分后再验证动画期间不再全量重建。
- **风险/遗留**：需要设计行级失效机制（Equatable 行子视图 + 按 id 的几何订阅）。

### C11 暂缓

- **结论**：每帧执行 `View.init` 中的布局缓存查找（12 字段哈希 + 深比较）仍在，未改代码。
- **原因**：`SynchronizedLyricText` 的 init 位于 `LyricRowPresentationTimeline` 的 TimelineView 内容闭包内，每帧执行，调用 `SynchronizedLyricTextLayout.resolve` 先哈希 12 字段 Key，命中后再用 `==` 深比较整行 `LyricLine`（含 syllables/romanizationSyllables 数组）。
- **改动**：未改；修复需要让 `SynchronizedLyricText` 可 Equatable 并加 `.equatable()`（参数含大量闭包与 Color，不可直接比较），或把 layout 提升到行容器，改动面大且无法编译验证。
- **文件**：—（报告引用 `MeloX/Features/Player/Lyrics/AppleMusic/LyricRowPresentationTimeline.swift`、`MeloX/Features/Player/Lyrics/Shared/SynchronizedLyricText.swift`）
- **提交**：—
- **验证**：读 LyricRowPresentationTimeline 16-27 确认 content 闭包每帧执行，读 init 中的 resolve 调用与 SynchronizedLyricTextLayout 185-201 的深比较；静态核对，未编译。
- **手测**：高刷设备播放，用 Time Profiler 观察 `SynchronizedLyricTextLayout.resolve` 与整行相等比较的采样占比。
- **风险/遗留**：需要重构行视图身份/Equatable 边界。

### C12 暂缓（部分已修复）

- **结论**：文字缓存淘汰策略由 FIFO 改为 LRU，但 Key 仍按 syllables 数组哈希，未做 lineID 化。
- **原因**：`LyricTextCache` 使用 `[Key: Text]` 加 insertionOrder，超过 256 条按插入顺序淘汰（FIFO）；较早插入但仍可能停留在屏幕上的行会被移出，miss 后在主线程重跑 CoreText 断行。
- **改动**：storage 改为 `[Key: Entry]`，`Entry` 记录 lastAccess tick；`text(for:)` 命中时更新 tick，insert 超限时淘汰 lastAccess 最小的一条；删除 insertionOrder；Key 仍按 syllables 数组哈希（避免跨歌曲同 ID 误命中）。
- **文件**：`MeloX/Features/Player/Lyrics/Shared/TimedLyricTextBuilder.swift`
- **提交**：`c6c0697`
- **验证**：读原 511-548 与调用方 `SynchronizedLyricTextLayout.text(from:constrainedWidth:...)`，确认方法签名未变、缓存类仍在 @MainActor；静态核对，未编译。
- **手测**：长歌词滚动，确认文字不闪烁，Instruments 观察 CTTypesetter 调用次数。
- **风险/遗留**：低；淘汰策略只影响命中率，不改变生成的 Text；剩余工作是把 Key 改为 lineID + 内容修订号，避免整段音节哈希。

### C14 暂缓（部分已修复）

- **结论**：逐字高亮渐变改为每次 draw 预计算一次，发光模糊图层缓存未做。
- **原因**：`LyricGlowTextRenderer.draw(layout:in:)` 每帧执行，`revealMask` 对每个 timed run 都调用 `highlightGradient` 新建 `stopCount+1` 个 `Gradient.Stop` 数组；一行几十个字符 run 时每帧几十次分配。
- **改动**：在 `draw(layout:in:)` 入口用 `makeRevealGradients()` 按当前 reduction 预计算左右两个 Gradient，逐 run 通过 `gradients.gradient(for:)` 复用；draw/revealMask 增加 gradients 参数。
- **文件**：`MeloX/Features/Player/Lyrics/Shared/LyricGlowTextRenderer.swift`
- **提交**：`b624849`
- **验证**：读原 260-283 的 `highlightGradient` 与 revealMask 调用链，确认 gradient 只依赖 reduction 与 layoutDirection、不依赖 playbackTime；静态核对，未编译。
- **手测**：逐字歌词播放，确认高亮渐变方向（含 RTL 歌词）与修改前一致。
- **风险/遗留**：低；Gradient 内容与原算法相同；剩余工作是缓存发光模糊图层。

### C15 暂缓（部分已修复）

- **结论**：仅把 EVA 排版计算移出子视图自身的 GeometryReader；父级重建时 init 仍会重新计算，没有持久缓存，原 REVIEW 的反复排版问题尚未完全解决。
- **原因**：`EVALyricCompositionView` 在 GeometryReader 闭包里每次 body/geometry 求值都调用 `EVALyricLayoutEngine.composition`（归一化文本、Array 字符、shuffle、计算所有 block frame），外层还有 `.id(currentLine.id)` 强制重建。
- **改动**：把 composition 提升为 `private let`，在新增的 `init(text:fontScale:layoutSeed:layoutSequence:)` 中按 text+seed+sequence 计算一次；body 只读 `composition.blocks`。
- **文件**：`MeloX/Features/Player/Lyrics/EVA/EVALyricCompositionView.swift`
- **提交**：`05433aa`
- **验证**：读 EVALyricsLayout 37-41 确认 composition 只依赖 source/sessionSeed/sequence 且与尺寸无关，EVALyricsView 62-68 调用点使用相同 init 标签；静态核对，未编译。
- **手测**：进入 EVA 歌词页后旋转设备、改变字号或触发父视图更新，用 Instruments/调用次数确认重算频率；不得预设已实现跨重建缓存。
- **风险/遗留**：init 标签与顺序不变、composition 是值类型；但这是 View init 计算——`EVALyricsView.swift:53-68` 把该视图构造在**另一层父 GeometryReader 内**，父几何失效仍会重建子视图并重跑 init，所以"旋转后完全不再重排"的表述过强；准确说法是只把计算移出子视图自身的 GeometryReader，且没有持久缓存。因此复核降为部分修复；剩余工作是基于 text/seed/sequence 的持久缓存或受控 State 失效，需另行实现与验证。

### C16 暂缓

- **结论**：每行线性查找下载状态并订阅下载进度的问题仍在，未改代码。
- **原因**：`TrackRowView.playbackMetadata` 每行每次渲染调用 `downloads.isDownloading/contains`，而 `DownloadStore.contains` 是 `downloads.contains` 的线性扫描；读取 `activeDownloads` 字典又让所有行订阅下载进度，进度回调推动整列表重渲染。
- **改动**：未改；O(1) 索引只能解决 contains，真正开销来自行级观察隔离（需要 Equatable 行或按 song 拆 store），会改动 `DownloadStore` 与多个列表，回归面大。
- **文件**：—（报告引用 `MeloX/Core/Downloads/DownloadStore.swift`、`MeloX/Shared/Media/TrackRowView.swift`）
- **提交**：—
- **验证**：读 DownloadStore 114-116 与 TrackRowView 163-164，确认线性 contains 与全行读取 activeDownloads；静态核对，未编译。
- **手测**：长下载列表同时下载多个文件，观察滚动时列表是否整体重绘。
- **风险/遗留**：需要行级观察隔离或下载状态索引，改动跨 Store 与多个列表。

### C17 已修复

- **结论**：喜欢歌曲列表每个 body 只计算一次 `displayedSongs`，不再在 if/ForEach/overlay 各算一次。
- **原因**：`LibrarySongsView.body` 在 if、ForEach 和 overlay 中分别访问 `displayedSongs` 计算属性，每次都针对分页累积的 `favoriteSongs` 做全量 `localizedCaseInsensitiveContains`。
- **改动**：body 开头计算一次 `let songs = displayedSongs`，if/ForEach/overlay 统一使用；`emptyState` 改为 `emptyState(songs:)` 接收结果，不再自行读取计算属性。
- **文件**：`MeloX/Features/Library/LibrarySongsView.swift`
- **提交**：`1031ffa`
- **验证**：读原 body 39/57/111 三处访问与 `displayedSongs` 定义，确认 ForEach 仍使用 `[Song]` 的 Identifiable；静态核对，未编译。
- **手测**：喜欢歌曲页搜索、滚动、取消喜欢，确认列表和空状态正常。
- **风险/遗留**：低；每个 body 仍做一次过滤（未引入跨 body State 缓存），结果与原来一致。

### C18 暂缓

- **结论**：`downloadableSongIDs` 在 body 内反复构建全量 Set 并做整数组 onChange 比较的问题仍在，未改代码。
- **原因**：`downloadableSongIDs` 在 `PlaylistDetailContent` 参数、两个 toolbar builder 和 onChange 中各计算一次，每次都 `Set(downloads.downloads.map)` 加 `union(activeDownloads.keys)` 再过滤；onChange 还对整数组做相等比较，下载进度回调持续触发。
- **改动**：未改；需要 `DownloadStore` 提供增量 revision/downloadedIDs，并把结果从 body 传到各 toolbar，改动面大且无法编译验证。
- **文件**：—（报告引用 `MeloX/Features/Playlist/PlaylistDetailView.swift`、`MeloX/Features/Playlist/PlaylistDetailContent.swift`）
- **提交**：—
- **验证**：读 PlaylistDetailView 102、189-192、341-350、396、434 的使用点，确认重复计算与数组比较；静态核对，未编译。
- **手测**：下载进行中停留在歌单页，用 Instruments 观察 `downloadableSongIDs` 的计算频率。
- **风险/遗留**：需要下载状态增量接口与 toolbar 传参重构。

### C19 暂缓

- **结论**：首页 fallback 的 task id 含收藏数组导致任意收藏变化就重启整轮网络加载的问题仍在，未改代码。
- **原因**：`HomeRecommendedFallbackLoadRequest` 的 task id 包含 `favoritePlaylistIDs` 与 `likedSongID`，任何收藏变化都会取消当前任务、经过 250ms 抖动后重启整轮 fallback 网络加载；而 loader 内部确实读取 `library.favoritePlaylists` 与 `likedSong` 参与推荐过滤。
- **改动**：未改；直接移出 id 会让收藏变化后的 fallback 内容变陈旧；报告建议的独立 debounce effect 需要产品决策（是否即时刷新）并新增订阅逻辑。
- **文件**：—（报告引用 `MeloX/Features/Home/HomeRecommendedView.swift`、`MeloX/Features/Home/HomeRecommendationFallbackLoader.swift`）
- **提交**：—
- **验证**：读 HomeRecommendedView 46-61、loader 34-35 与 265，确认依赖与重启链路真实存在；静态核对，未编译。
- **手测**：在首页反复收藏/取消收藏歌单，用 Network 面板观察是否触发整轮 fallback 请求。
- **风险/遗留**：需要产品先决定"收藏后是否即时刷新推荐"。

### C20 已修复

- **结论**：详情封面资产增加 in-flight 去重，同一 URL 并发请求只下载/处理一次。
- **原因**：`detailAssets` 只在处理完成后写入 NSCache；actor 在 await URLSession 期间让出执行权，NowPlayingBackground、AlbumDetail、导航转场等并发请求同一 URL 时会各自下载并各跑一遍降采样、直方图和模糊。
- **改动**：新增 actor 内 `inFlightLoads: [URL: Task<ArtworkDetailAssets, Never>]`；`detailAssets` 命中缓存后优先 await 已存在的 Task，否则创建共享 Task 并登记，完成后清理；下载与图像处理逻辑移入 `private loadDetailAssets`。
- **文件**：`MeloX/Core/Artwork/ArtworkAccentColorProvider.swift`
- **提交**：`ea99562`
- **验证**：读原 113-135 与调用方（detailPalette/accentColor/PlaylistDetailView.task），确认 actor 串行执行保证先登记再 await、Task 为 Never 不抛出；静态核对，未编译。
- **手测**：快速反复进入同一专辑详情与播放页，用 Network 面板确认同一封面只下载一次。
- **风险/遗留**：中低；并发时首个调用者的 `fallbackPrefersDarkAppearance` 会被共享，失败兜底的深浅色可能取首个请求的值（同一系统外观下无实际差异）。

### C21 已修复

- **结论**：封面下载改用 `useProtocolCachePolicy`，不再强制绕过 URLCache。
- **原因**：`ArtworkDataLoader.data` 固定使用 `reloadIgnoringLocalCacheData`，Live Activity 与通知封面每次都绕过 URLCache 重新下载。
- **改动**：改为 `useProtocolCachePolicy`，遵循服务器缓存头；调用方自身的 songID/URL 进程内缓存保持不变。
- **文件**：`MeloX/Core/Artwork/ArtworkDataLoader.swift`
- **提交**：`6bf8431`
- **验证**：读 `LyricsLiveActivityArtworkStore.swift:59-75` 与 `Notifications/LyricsNotificationArtworkStore.swift:66`，确认已有进程内缓存且不要求每次强制刷新；静态核对，未编译。
- **手测**：重复播放同一首歌并查看 Live Activity 封面，用 Network 面板确认第二次不再发起图片请求。
- **风险/遗留**：低；若服务器在同一 URL 下更换封面，需等缓存头过期才更新（封面 URL 通常按内容寻址）。

### C23 暂缓

- **结论**：专辑列表在 body 内做全量 ICU 搜索属项目既有模式，收益有限，未改代码。
- **原因**：`LibraryAlbumsView.body` 直接对 `favoriteAlbums` 做两个字段的 `localizedCaseInsensitiveContains` 过滤，任何状态变化（phase、dynamicTypeSize、下载/播放）都会重跑。
- **改动**：未改；该写法与 `LibraryArtistsView`/`LibrarySongsView` 的既有模式一致，每次 body 只过滤一次；跨 body 缓存需要 State 与收藏/搜索同步，收益有限且容易出现陈旧结果。
- **文件**：—（报告引用 `MeloX/Features/Library/LibraryAlbumsView.swift`）
- **提交**：—
- **验证**：读 10-16 与 `LibraryArtistsView` 7-11 的同类实现，确认是项目既有模式；静态核对，未编译。
- **手测**：收藏专辑较多时切换搜索并滚动，观察主线程占用。
- **风险/遗留**：属性能增强，需先测出实际热点再决定是否引入缓存。

### C24 已修复

- **结论**：下载列表每个 body 只计算一次进行中/已完成集合，不再按访问次数重复排序。
- **原因**：`activeDownloadSongs` 计算属性在 body 的 section 判断、ForEach 和空状态中分别访问，每次都要 `Array(activeSongs.values)`、过滤并按 `localizedCompare` 排序；`filteredDownloads` 与 `filteredDownloadedSongs` 也被重复访问。
- **改动**：body 开头一次性计算 `activeSongs = activeDownloadSongs`、`downloaded = filteredDownloads`、`playableSongs = downloaded.map` 提取 song，后续统一使用；删除不再使用的 `filteredDownloadedSongs`。
- **文件**：`MeloX/Features/Library/LibraryDownloadsView.swift`
- **提交**：`01810aa`
- **验证**：读原 24/26/39/41/57/76 的访问点，确认 ForEach 仍使用 Identifiable、`filteredDownloadedSongs` 已无引用；静态核对，未编译。
- **手测**：下载进行中打开下载列表并搜索，确认进行中/已完成区段和空状态正确。
- **风险/遗留**：低；下载进行中每个 body 仍会排序一次，但不再按访问次数重复排序。

### C25 已修复

- **结论**：歌单曲目列表不再每次 body 构造 `Array(tracks.enumerated())`。
- **原因**：`PlaylistTrackList.body` 每次求值 `ForEach(Array(tracks.enumerated()), id: element.id)` 都会为整张歌单新建 `(offset, Song)` 元组数组。
- **改动**：改为 `ForEach(tracks.indices, id: self) { index in let song = tracks[index] … }`，行内仍显式 `.id(song.id)`；不再分配 enumerated 数组。
- **文件**：`MeloX/Features/Playlist/PlaylistTrackList.swift`
- **提交**：`ad6173c`
- **验证**：读 21 与行内 index 使用（行号、Divider、PlaylistTrackRow.index），确认 tracks 非空由外层 if 保证；静态核对，未编译。
- **手测**：在歌单中删除或重排歌曲，确认行动画、行号和高亮正常。
- **风险/遗留**：低；ForEach 容器身份由 `song.id` 变为 index（每行仍显式 `.id(song.id)`），插入/删除/重排时的容器身份与滚动位置需真机确认。

### C26 暂缓（部分已修复）

- **结论**：行移除时会停止无限循环位移动画，但未按 isPlaying/scenePhase 暂停。
- **原因**：`SkylineAmbientLyricText` 在 `onAppear` 启动 `repeatForever` 位移动画，只在 `reduceMotion` 变化时停止；行离屏或页面退出后动画仍持续合成。
- **改动**：增加 `.onDisappear { withAnimation(nil) { isDrifting = false } }`，行移除时停止无限动画；未按 isPlaying/scenePhase 暂停，因为该子视图没有这些输入。
- **文件**：`MeloX/Features/Player/Lyrics/Skyline/SkylineAmbientLyricsView.swift`
- **提交**：`fdb7c08`
- **验证**：读 `SkylineAmbientLyricText` 的 onAppear/onChange 与 `startDrifting` 实现，确认 onDisappear 与现有 modifier 链一致；静态核对，未编译。
- **手测**：离开播放页再返回，用 Instruments 确认离屏后不再有持续的动画合成。
- **风险/遗留**：低；离屏行不可见，重新出现时 onAppear 会重启动画；剩余工作是让子视图接收 isPlaying/scenePhase 以便暂停。

### C27 暂缓（有意设计）

- **结论**：流光背景 20Hz 刷新是设计刷新率，且暂停/后台/减弱动态时已停止，未改代码。
- **原因**：`NowPlayingFlowingLightBackground` 用 20Hz TimelineView 重建 MeshGradient 与多个渐变层，但 `pausesAnimation` 已覆盖 reduceMotion、isLuminanceReduced、scenePhase 非活跃和 player 未播放。
- **改动**：未改；降低频率或交给 Core Animation 属视觉/产品决策，当前环境无法验证效果。
- **文件**：—（报告引用 `MeloX/Features/Player/NowPlaying/NowPlayingFlowingLightBackground.swift`）
- **提交**：—
- **验证**：读 25-60 与 `pausesAnimation` 定义，确认暂停条件；静态核对，未编译。
- **手测**：播放/暂停/切后台观察背景是否停止刷新，再评估是否需要降到 10-15Hz。
- **风险/遗留**：无（未改动）。

### C28 暂缓（部分已修复）

- **结论**：缩略图请求尺寸改为乘 displayScale（修复 3x 屏请求过小），内层 GeometryReader 未去除。
- **原因**：`ArtworkImage` 每个封面单元都套 GeometryReader 先测量再构造 `ImageRequest`，并且 `ThumbnailOptions.size` 直接使用 SwiftUI points；Nuke 按 pixels 解释该尺寸，3x 屏会请求到三分之一分辨率。
- **改动**：新增 `@Environment(displayScale)`，thumbnail 尺寸乘以 `max(displayScale, 1)`；去掉内层 GeometryReader 需要父布局传入确定尺寸（大量调用点），未做。
- **文件**：`MeloX/Shared/Media/ArtworkImage.swift`
- **提交**：`36570c7`
- **验证**：读 body 与 `imageRequest`，确认 Nuke 的 `ThumbnailOptions` 尺寸单位为 pixels、`displayScale` 为 SwiftUI 环境值；静态核对，未编译。
- **手测**：在 3x 设备上查看网格封面清晰度与滚动流畅度，确认不再模糊。
- **风险/遗留**：低；缓存键随尺寸变化会多占少量内存、首次加载像素量上升；剩余工作是去除 GeometryReader 并让父布局传确定尺寸。

## 5.7 b7-sec-build-l10n（25 条）

### F0 暂缓

- **结论**：网易云会话 Cookie 明文存 UserDefaults 属实，改 Keychain 需要迁移与实机验证，未改代码。
- **原因**：`MeloX/Core/Settings/Application/AppSettings.swift:281-283` 的 cookie `didSet` 直接 `defaults.set(cookie, forKey: Key.cookie)`（`Key.cookie` 为 `musicCookie`），全仓库没有 Keychain 调用；`PageContentCache.scope(for:)` 还把该 Cookie 作为缓存 scope 的 SHA256 输入。
- **改动**：未改代码；需要新增 SecItemAdd/SecItemUpdate/SecItemCopyMatching、旧 musicCookie 迁移、写入失败回退与日志，两端没有可共用的凭据文件，且无法在本环境验证签名/entitlement 下的 Keychain 行为。
- **文件**：—（报告引用 `MeloX/Core/Settings/Application/AppSettings.swift`、`MeloX/Core/Storage/PageContentCache.swift`）
- **提交**：—
- **验证**：读 cookie didSet、init 中 `defaults.string(forKey: Key.cookie)`、PageContentCache:57；grep `kSecClass/SecItemAdd/SecItemCopyMatching/Keychain` 均无结果；静态核对，未编译。
- **手测**：未来实现后：登录后杀进程重开仍保持登录；旧版升级迁移成功且 plist 中该键被删；退出登录后 Keychain 项被删；未加密备份不出现 MUSIC_U。
- **风险/遗留**：直接改会触及核心登录路径；无签名/ad-hoc 构建或 `errSecMissingEntitlement` 时可能让已登录用户丢会话。

### F1 暂缓

- **结论**：macOS 端同样把会话 Cookie 明文存 UserDefaults 属实，需与 F0 共用方案，未改代码。
- **原因**：`MeloXDesktop/Core/Settings/Application/AppSettings.swift:288-290` 的 cookie `didSet` 同样直接写 UserDefaults（`Key.cookie` 为 `musicCookie`）；桌面端也没有 Keychain 代码。
- **改动**：未改代码；需要与 F0 共用同一 CredentialStore 方案，而 iOS/macOS 是两份独立 AppSettings，新增共享源文件违反本批次限制；macOS target 开启 app-sandbox 且发布用 ad-hoc 签名，Keychain 行为必须实机验证后才能改。
- **文件**：—（报告引用 `MeloXDesktop/Core/Settings/Application/AppSettings.swift`）
- **提交**：—
- **验证**：读 macOS cookie didSet 与 init；grep 无 Keychain 调用；pbxproj:844/879 确认 `ENABLE_APP_SANDBOX = YES`；静态核对，未编译。
- **手测**：未来实现后：macOS 登录后重启仍保持登录；旧版升级迁移成功；Keychain Access 有对应项且 plist 无 musicCookie；ad-hoc 重建不反复弹授权。
- **风险/遗留**：沙盒/ad-hoc 下 Keychain 可能返回 `errSecMissingEntitlement` 或反复弹授权，直接改可能让桌面端无法保持登录。

### F2 暂缓

- **结论**：手机把完整登录 Cookie 经 WCSession 复制到手表并落盘属实，需先设计凭证方案，未改代码。
- **原因**：`PhoneWatchSyncService.makeSnapshot`（`MeloX/Core/Watch/PhoneWatchSyncService.swift:61-71`）把完整 `settings.cookie` 放进 `MeloXWatchAccountSnapshot`；手表 `WatchAccountStore.save`（第109行）用 `defaults.set` 存到 `melox.watch.cookie`；手机 `handle(.account)` 第80行又反向 `settings.cookie = account.cookie`。
- **改动**：未改代码；要停止持久化原始 MUSIC_U 需要服务端短期播放凭证，或两端 Keychain + ThisDeviceOnly + 迁移，并重新定义扫码覆盖手机、退出登录是否清手表等产品语义。
- **文件**：—（报告引用 `MeloX/Core/Watch/PhoneWatchSyncService.swift`、`MeloXWatch/Account/WatchAccountStore.swift`、`MeloXWatchShared` 的同步模型）
- **提交**：—
- **验证**：读 PhoneWatchSyncService 61-71/78-81、WatchAccountStore 25/48/109、快照编解码，确认 Cookie 会经 WCSession 到手表并落盘；静态核对，未编译。
- **手测**：未来实现后：手机登录→手表可播放；手机退出→手表同步退出；读手表 UserDefaults 不再出现 MUSIC_U；手表重新扫码不静默覆盖手机账号。
- **风险/遗留**：简单从 snapshot 删除 cookie 会让手表无法登录；只改手表 Keychain 而手机仍明文，且当前 logout 不会清手表 Cookie。

### F3 已修复

- **结论**：隐私文案不再声称 Cookie"仅保存在本机"，改为说明会同步到已配对 Apple Watch。
- **原因**：`Localizable.strings` 第381行与 zh-Hans 同 key 声称 Cookie 仅保存在本机/本设备，但 `PhoneWatchSyncService.makeSnapshot` 会把 cookie 发到手表并持久化；onboarding 的 `ui.onboarding.benefit.local_cookie`（两语言第964行）同样不准确。
- **改动**：更新 `ui.settings.account.cookie.footer`（英文说明也会共享给已配对 Apple Watch，中文同步），`ui.onboarding.benefit.local_cookie` 中英文改为"仅保存在你的设备上"；两个 key 在两份 `Localizable.strings` 保持一致，未新增/删除 key。
- **文件**：`MeloXLocalization/en.lproj/Localizable.strings`、`MeloXLocalization/zh-Hans.lproj/Localizable.strings`
- **提交**：`d3ef15f`
- **验证**：读 PhoneWatchSyncService 61-71 与 WatchAccountStore:109 确认数据流；grep 确认两 key 只在三处使用，两种语言最终行均为 381/964；静态核对，未编译。
- **手测**：设置→账号与 iOS/macOS onboarding 分别切中英文，确认 footer/benefit 与手表同步行为一致，不再出现"仅保存在本机"。
- **风险/遗留**：无编译风险；若后续 F2 决定停止手表同步，需要把 footer 改回仅本机；macOS onboarding 复用同一 key，但"你的设备"表述对 Mac 仍成立。

### F4 已修复

- **结论**：第三方歌词源（AMLL / QQ）默认关闭，默认 automatic 模式只请求网易云。
- **原因**：iOS `AppSettings.swift:1557-1562`（macOS 1589-1594）把 `lyricsAMLLSourceEnabled/lyricsQQMusicSourceEnabled` 缺省为 true；`LyricsService.load` 在 automatic 模式下按开关请求 `amlldb.bikonoo.com` 与 `u.y.qq.com`；`resetPlayerSettings` 也把两者重置为 true。
- **改动**：iOS 与 macOS 的两个 init 默认值改为 false，`resetPlayerSettings` 重置值改为 false；用户主动打开开关或手动选择来源才访问第三方。
- **文件**：`MeloX/Core/Settings/Application/AppSettings.swift`、`MeloXDesktop/Core/Settings/Application/AppSettings.swift`
- **提交**：`5c5e8a7`
- **验证**：读 LyricsService 40-50 的 `usesSource`、AMLLLyricsClient:12、QQMusicLyricsClient:161；grep 确认只有 init 默认值与 reset 会置 true；静态核对，未编译。
- **手测**：清空 UserDefaults 后播放一首网易云歌词不全的歌，抓包确认没有 amlldb.bikonoo.com 与 u.y.qq.com 请求；打开开关后应出现；恢复默认后两个开关应为关。
- **风险/遗留**：行为变化：未显式开启的用户默认不再使用 AMLL/QQ 补全，歌词命中率可能下降；已保存为 true 的用户不受影响。

### F5 已修复

- **结论**：登录时只接受 `music.163.com` 的 Cookie，不再把任意 `*.163.com` Cookie 合并进会话。
- **原因**：`NeteaseLoginView.swift:68-79` 的 `authenticatedCookieHeader` 用 `isNeteaseCookie` 收集任意 `*.163.com` Cookie 并拼进 `settings.cookie`；登录 WebView 可能经过 reg/urs/mail 等子域，导致非音乐服务 Cookie 进入音乐 API；`DesktopLoginView.swift:120-154` 是同一份逻辑。
- **改动**：新增 `isUsableAccountCookie`，只接受 domain 规范化后等于 `music.163.com` 且未过期的 Cookie；`authenticatedCookieHeader` 改用它，`clear()` 仍用 `isNeteaseCookie` 清理所有 163.com Cookie；iOS 与 macOS 两份实现同步修改。
- **文件**：`MeloX/Features/Settings/Account/NeteaseLoginView.swift`、`MeloXDesktop/Features/Account/DesktopLoginView.swift`
- **提交**：`479579e`
- **验证**：读两份原实现与 MUSIC_U guard，确认 MUSIC_U/__csrf 来自 music.163.com；没有加名称白名单以避免漏掉音乐服务自身必需 Cookie；静态核对，未编译。
- **手测**：退出后重新网页/扫码登录，确认能进入账号；用代理检查后续 Cookie 头只含 music.163.com 来源；退出登录后 WKWebsiteDataStore 中 163.com Cookie 被清理。
- **风险/遗留**：若登录流程把 MUSIC_U 写在 `.163.com` 而非 `music.163.com`，登录会一直等待；当前网易网页登录的 MUSIC_U 在 music.163.com，风险低（列为待真机确认的风险，不是已证实缺陷）。

### F6 已修复

- **结论**：云盘上传地址要求 HTTPS 且命中受信任 NOS 域名，http 或恶意主机不再带 token 外发。
- **原因**：`NeteaseDirectClient.uploadToNOS` 把 LBS 响应 `lbs.upload.first` 直接字符串拼成 URL 并 POST 音频，未校验 scheme/host；iOS 与 macOS 副本相同。
- **改动**：构造 `uploadURL` 后新增 `isAllowedUploadURL`：要求 scheme 为 https、host 非空且属于 `127.net/126.net/netease.com/163.com/163yun.com` 或其子域，否则抛 `APIError.requestEncoding`；两端同步修改。
- **文件**：`MeloX/Core/Networking/NeteaseDirectClient.swift`、`MeloXDesktop/Core/Networking/NeteaseDirectClient.swift`
- **提交**：`225b104`
- **验证**：读 116-178、`NOSLBSResponse` 定义与 `Tests/Networking/WEAPITransportChecks.swift`，确认 token 在 URL 构造后加入 `x-nos-token`、测试脚本只抽取 weapi/formEncodedData；静态核对，未编译。
- **手测**：云盘上传一首歌应成功；用代理把 LBS 的 upload 改成 `http://example.com` 或 `https://example.com`，上传应失败且确认没有带 `x-nos-token` 的请求发出。
- **风险/遗留**：若 NOS LBS 返回未列入白名单的合法上传域（新 CDN 或 IP），云盘上传会以 requestEncoding 失败；只校验初始 URL、不校验重定向目标；上线前应按真实 LBS 响应补充白名单。

### F7 暂缓

- **结论**：缺少 PrivacyInfo.xcprivacy 属实，但新增资源文件并加入两个 target 需要改 pbxproj，未改代码。
- **原因**：`StorageMaintenance.swift:184` 使用 `volumeAvailableCapacityForImportantUsageKey`、261/266 使用 `contentModificationDateKey`，AppSettings 大量使用 UserDefaults；仓库除 `vendor/QRCode` 外没有 `PrivacyInfo.xcprivacy`，pbxproj 中也没有引用。
- **改动**：未改代码；需要新增 `PrivacyInfo.xcprivacy` 并加入 MeloX 与 MeloX Desktop target，新增文件与 pbxproj 编辑都被本批次硬性规则禁止，且无 Xcode 无法验证资源打包。
- **文件**：—（报告引用 `MeloX.xcodeproj/project.pbxproj`、`MeloX/Core/Storage/StorageMaintenance.swift`）
- **提交**：—
- **验证**：读 required-reason API 调用；glob 只在 `vendor/QRCode` 找到 PrivacyInfo.xcprivacy；grep pbxproj 无 PrivacyInfo；静态核对，未编译。
- **手测**：未来添加后 `plutil -lint` 校验，并上传 TestFlight 确认不再收到 ITMS-91053。
- **风险/遗留**：未修复时 App Store Connect 仍可能出现 ITMS-91053；不影响本地编译。

### F8 暂缓

- **结论**：歌词组件 CFBundleVersion 与主 App 不一致属实，但版本值只在 pbxproj 中，未改代码。
- **原因**：`project.pbxproj:518` 的 `MeloXLyricsWidget CURRENT_PROJECT_VERSION` 为 9110300，而主 App 第678行为 9110401、watch 第761行为 9110401；Info.plist 都引用 `$(CURRENT_PROJECT_VERSION)`。
- **改动**：未改代码；正确修法是抽 xcconfig 或让各 target 共用同一版本变量，本批次禁止编辑 pbxproj。
- **文件**：—（报告引用 `MeloX.xcodeproj/project.pbxproj`）
- **提交**：—
- **验证**：读 pbxproj 511-520、670-680、754-763，确认三处版本差异与 Info.plist 引用；静态核对，未编译。
- **手测**：构建后分别 `plutil -p` 三个 Info.plist，确认 CFBundleVersion 相等。
- **风险/遗留**：保持现状可能在上传时触发 Invalid Bundle（extension 与宿主 CFBundleVersion 不一致）。

### F10 暂缓

- **结论**：非 Ranco7 仓库上构建成功却不上传产物属实，但工作流属禁止编辑范围，未改代码。
- **原因**：`.github/workflows/unsigned-ios-ipa.yml:122-123` 的 artifact 上传条件是 `github.ref != 'refs/heads/codex/ipad-adaptive-layout'`，而第131-132行发布条件写死 `github.repository == 'Ranco7/MeloX'` 且 ref 必须是该分支；在其他仓库/分支构建成功但两个出口都跳过。
- **改动**：未改代码；建议无条件上传 artifact，并把发布条件改为仓库变量（如 `vars.PUBLISH_IPA == 'true'`）。
- **文件**：—（报告引用 `.github/workflows/unsigned-ios-ipa.yml`）
- **提交**：—
- **验证**：读 122-132，条件与报告一致；静态核对，未运行 CI。
- **手测**：在 fork 上手动运行该 workflow，确认 Actions 运行页出现 artifact；发布步骤只在配置变量为 true 的仓库执行。
- **风险/遗留**：CI 会静默不产出可下载包，维护者可能误以为已上传。

### F12 暂缓（有意设计）

- **结论**：`screen-capture` 后台模式很可能是为 iOS 27 ScreenCaptureKit 预留，报告前提不成立，未改代码。
- **原因**：`MeloX/Info.plist:44-47` 确有 screen-capture，但仓库并非没有截屏/系统音频实现——`SongRecognitionAppAudioCapture.swift` 使用 ReplayKit，`SongRecognitionSystemAudioCapture.swift` 使用 iOS 27 的 ScreenCaptureKit，`SongRecognitionAudioSource.availableCases` 在 iOS 27 提供 systemAudio。
- **改动**：未改代码；删除可能在 iOS 27 上破坏跨 App 系统音频识别，保留则当前 App Store Connect 可能对未知值告警，需发版配置决策。
- **文件**：—（报告引用 `MeloX/Info.plist`、`MeloX/Features/SongRecognition/SongRecognitionAppAudioCapture.swift`、`SongRecognitionSystemAudioCapture.swift`）
- **提交**：—
- **验证**：读 Info.plist 44-48 与三个源文件，并用 web search 查到 Apple 开发者论坛提到 iOS 27 ScreenCaptureKit 示例使用该值、但 App Store Connect 可能拒绝；静态核对，未编译。
- **手测**：在 iOS 27 真机用 System Audio 识别并切到后台，确认采集是否继续；同时用对应 Xcode 的 App Store 校验检查 plist。
- **风险/遗留**：保留可能触发上传校验告警；删除可能破坏 iOS 27 ScreenCaptureKit 后台采集。

### F13 已修复

- **结论**：macOS 系统音频采集权限说明补齐中英文，中文系统不再显示英文弹窗。
- **原因**：`MeloXDesktop/Info.plist:32-33` 有 `NSAudioCaptureUsageDescription`，但 `MeloXDesktop/en.lproj/InfoPlist.strings` 与 zh-Hans 原先只有 `NSMicrophoneUsageDescription`。
- **改动**：在两个 `InfoPlist.strings` 中追加 `NSAudioCaptureUsageDescription` 的英文/中文文案，与 Info.plist 语义一致；原有 `NSMicrophoneUsageDescription` 行不变。
- **文件**：`MeloXDesktop/en.lproj/InfoPlist.strings`、`MeloXDesktop/zh-Hans.lproj/InfoPlist.strings`
- **提交**：`2940ba3`
- **验证**：读 `MeloXDesktop/Info.plist:30-33` 与两份 InfoPlist.strings 最终内容，确认 key 名一致、两个语言文件均以换行结尾；静态核对，未编译。
- **手测**：macOS 中文系统首次使用系统音频识别，权限弹窗应显示中文说明；切英文系统应显示英文说明。
- **风险/遗留**：无编译风险；若 Info.plist 缺少该 key 本地化不会生效（当前已存在）。

### F14 暂缓（有意设计）

- **结论**：手表已有独立语言设置，手机语言不传递是现有设计，未改代码。
- **原因**：报告描述的数据流属实：手机 `AppLanguage.selected` 读的是手机自己的 UserDefaults，未放进 `MeloXWatchSnapshot`；但手表已有独立的 `@AppStorage(AppLanguage.storageKey)` 与 `WatchSettingsView` 语言选择器，`MeloXWatchApp.init` 也会 `L10n.activate(AppLanguage.selected)`。
- **改动**：未改代码；把手机语言塞进 snapshot 会覆盖或冲突手表的独立选择，属产品决策，还要改同步模型、两端同步与手表激活逻辑。
- **文件**：—（报告引用 `MeloXLocalization/AppLanguage.swift`、`MeloXWatch/Settings/WatchSettingsView.swift`、`MeloXWatch/App/MeloXWatchApp.swift`）
- **提交**：—
- **验证**：读 AppLanguage 34-40、WatchSettingsView 4-20、MeloXWatchApp 5-18 与 53；静态核对，未编译。
- **手测**：分别在手机和手表设置不同语言，确认两端按现有独立设置工作；若产品要求跟随手机，再按新需求实现。
- **风险/遗留**：若未来做同步，需要先定义手机与手表冲突时谁优先；当前不改不会引入回归。

### F20 已修复

- **结论**：找不到 lproj 时在 Debug 下触发断言，不再静默回退 `Bundle.main` 显示 key。
- **原因**：`MeloXLocalization/L10n.swift` 的 `localizedBundle(named:)` 找不到 `en.lproj/zh-Hans.lproj` 时静默 `return .main`，导致所有 `L10n.string` 原样显示 key，且不同 target 行为难以定位。
- **改动**：在 `localizedBundle` 的 else 分支加入 `#if DEBUG assertionFailure`，消息包含缺失的 localization 与 `Bundle.main.bundleIdentifier`；Release 仍保留 `.main` 回退。
- **文件**：`MeloXLocalization/L10n.swift`
- **提交**：`ea5936f`
- **验证**：读 154-170 最终代码；pbxproj 的 MeloX、Watch、Desktop、LyricsWidget `fileSystemSynchronizedGroups` 都包含 `MeloXLocalization`（231/261/288/313 行），现有 target 正常构建不会触发；静态核对，未编译。
- **手测**：Debug 构建中临时移除某 target 的 en.lproj/zh-Hans.lproj，启动应触发断言并显示缺失目录；恢复资源后正常。
- **风险/遗留**：Debug 下缺 lproj 会触发断言崩溃；若 Xcode Preview 或未来测试 bundle 未打包本地化资源，也会在调试时暴露（Release 行为不变）。

### F23 已修复

- **结论**：手表把无等号的裸 MUSIC_U token 也识别为已登录。
- **原因**：`MeloXWatch/Account/WatchAccountStore.swift:48` 的 `isLoggedIn` 只检查 `cookie.contains("MUSIC_U=")`，而手机 `NeteaseDirectClient.cookieValues` 明确支持无等号的裸 MUSIC_U token；裸 token 同步到手表后会被判为未登录。
- **改动**：`isLoggedIn` 先 trim；空串返回 false；不含等号的非空串按手机语义视为裸 MUSIC_U token 返回 true；含等号时仍检查 `MUSIC_U=`。
- **文件**：`MeloXWatch/Account/WatchAccountStore.swift`
- **提交**：`f46b09b`
- **验证**：读 47-53 最终代码、`NeteaseDirectClient.cookieValues` 与 `PhoneWatchSyncService.makeSnapshot`，逻辑与手机侧裸 token 支持一致；静态核对，未编译。
- **手测**：把 `settings.cookie` 设为无等号的裸 MUSIC_U token，同步后手表应显示已登录并能请求；再测完整 `MUSIC_U=...; __csrf=...` 头仍正常。
- **风险/遗留**：若裸 token 本身包含等号，仍会走完整 Cookie 解析（与手机侧现有行为一致）；本次只修登录态判断，不改变存储。

### F9 暂缓

- **结论**：Telegram 密钥作业会对同仓库 PR 运行属实（风险较低），但工作流属禁止编辑范围，未改代码。
- **原因**：`build-unsigned.yml:215-220` 的 telegram job 对同仓库 PR 成立，285 行注入 `TELEGRAM_BOT_TOKEN`；同仓库 PR 可修改 `build_ios_unsigned.sh` 或工作流本身来读取该 token。
- **改动**：未改代码；建议把 telegram job 限制为 push 到 main 或 tag，或用 environment + required reviewers 保护。
- **文件**：—（报告引用 `.github/workflows/build-unsigned.yml`）
- **提交**：—
- **验证**：读 215-220、282-286，条件与 secret 注入位置一致；静态核对，未运行 CI。
- **手测**：同仓库分支开 PR 后确认 telegram job 不再运行；push main/tag 时才运行且需要 environment 审批。
- **风险/遗留**：有分支写权限的人（含被盗账号）可在 PR 构建中拿到 bot token 并分发未审阅二进制。

### F11 暂缓

- **结论**：App Group 权限未被业务代码使用、legacy 脚本也不同步改组名属实，但 entitlements 与构建脚本禁止编辑，未改代码。
- **原因**：`MeloX/MeloX.entitlements:5-7` 声明 `group.azki.moye.MeloX`，但 grep 只在 OnboardingView 的测试随机 suiteName 和测试脚本命中，业务代码没有使用该 App Group；`build_ios_unsigned.sh:55-66` 的 legacy 变体只改 bundle id/team，不改组名。
- **改动**：未改代码；若确认不用应删除 entitlement，若要用则在 legacy 变体同步重写组名。
- **文件**：—（报告引用 `MeloX/MeloX.entitlements`、`build_ios_unsigned.sh`）
- **提交**：—
- **验证**：读 entitlements、脚本 37-67，并 grep `UserDefaults(suiteName:)`/`containerURL(forSecurityApplicationGroupIdentifier:)`，未发现业务用途；静态核对，未编译。
- **手测**：删除 entitlement 后构建并确认无代码依赖；检查 legacy IPA 的 entitlements 与 bundle id 一致。
- **风险/遗留**：保留无用权限违反最小权限；未来启用共享容器时 legacy 产物会静默拿不到容器。

### F15 暂缓

- **结论**：target 级关闭 User Script Sandboxing 属实，但 pbxproj 禁止编辑，未改代码。
- **原因**：`project.pbxproj` 项目级 `ENABLE_USER_SCRIPT_SANDBOXING` 为 YES，但 MeloX/Watch/Desktop target 在 682/847/882 等行覆盖为 NO；这些 target 有执行 python/git 的 Run Script 阶段。
- **改动**：未改代码；正确修法是把 target 级恢复 YES，并为 release-notes 脚本补齐 inputPaths 或通过环境变量传入所需 git ref。
- **文件**：—（报告引用 `MeloX.xcodeproj/project.pbxproj`）
- **提交**：—
- **验证**：读 pbxproj 678-682、840-847、869-882，确认 target 覆盖；静态核对，未编译。
- **手测**：把 target 改为 YES 后完整构建，确认 Generate Release Notes 仍成功且不再访问 .git 之外路径。
- **风险/遗留**：关闭脚本沙箱会扩大构建脚本的文件系统访问面。

### F16 暂缓

- **结论**：工程写死第三方 Team ID 与描述文件名属实，但 pbxproj 与构建脚本禁止编辑，未改代码。
- **原因**：`project.pbxproj:676-680` 写死 `CODE_SIGN_STYLE = Manual`、`DEVELOPMENT_TEAM[sdk=iphoneos*] = LAW363CUU8`，697-698 写死 `PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*] = MeloX`；`build_ios_unsigned.sh` 只能在临时副本 sed 改写。
- **改动**：未改代码；建议把 team/profile 移到 xcconfig 或由 CI 通过 xcodebuild 参数注入，源码工程保持空值并启用自动签名。
- **文件**：—（报告引用 `MeloX.xcodeproj/project.pbxproj`、`build_ios_unsigned.sh`）
- **提交**：—
- **验证**：读 pbxproj 670-700 与脚本 55-66，硬编码值一致；静态核对，未编译。
- **手测**：在无该 team 的机器上用自己账号构建，确认可通过 xcodebuild 参数覆盖身份；legacy 脚本产物 bundle id/team 正确。
- **风险/遗留**：其他开发者本地构建/TestFlight 会因证书或描述文件不匹配失败；sed 改写身份脆弱。

### F17 暂缓

- **结论**：legacy 临时工程生成在仓库根且只靠 trap 清理属实，但构建脚本禁止编辑，未改代码。
- **原因**：`build_ios_unsigned.sh:37` 把临时 xcodeproj 放在仓库根 `.MeloX-Legacy-Build-$$.xcodeproj`，45 行 ditto 复制，清理只依赖 `trap cleanup_temporary_build_inputs EXIT INT TERM`；SIGKILL/断电会残留已改身份的工程副本。
- **改动**：未改代码；建议改用 `mktemp -d` 放到 TMPDIR，并在 `.gitignore` 加 `.MeloX-Legacy-Build-*` 兜底。
- **文件**：—（报告引用 `build_ios_unsigned.sh`）
- **提交**：—
- **验证**：读脚本 33-67，确认临时工程路径与 sed 改写逻辑、清理由 trap 保证；静态核对，未编译。
- **手测**：在临时工作区运行 legacy 构建并在中途 `kill -9`，确认 TMPDIR 有残留而仓库根没有；正常结束应无残留。
- **风险/遗留**：残留工程可能污染工作区或被误提交。

### F18 暂缓

- **结论**：DMG 用已弃用的 `--deep` 做 ad-hoc 签名、发布页教用户去 quarantine 属实，但脚本与 CI 禁止编辑，未改代码。
- **原因**：`build_macos_dmg.sh:111-117` 用 `codesign --force --deep --sign -` 做 ad-hoc 签名；`build-unsigned.yml` 的 Release 正文还指导用户 `xattr -dr com.apple.quarantine`。
- **改动**：未改代码；建议显式签名嵌套 Mach-O，并优先提供 Developer ID 签名 + 公证的 DMG，把去 quarantine 说明限制在官方下载页并附校验和。
- **文件**：—（报告引用 `build_macos_dmg.sh`、`.github/workflows/build-unsigned.yml`）
- **提交**：—
- **验证**：读脚本 104-117，确认 `--deep` 与 ad-hoc 签名；静态核对，未编译。
- **手测**：本地生成 DMG 后 `codesign --verify --strict` 检查嵌套组件；在未安装 profile 的 Mac 上打开，确认 Gatekeeper 行为符合发布说明。
- **风险/遗留**：未签名 + 关闭 Gatekeeper 降低下载完整性防护；`--deep` 掩盖嵌套签名问题。

### F19 暂缓

- **结论**：有 write 权限的发版作业使用可变 tag 的第三方 Action 属实，但工作流禁止编辑，未改代码。
- **原因**：`build-unsigned.yml:357-358` 的 release job 拥有 `contents: write`，545 行使用 `softprops/action-gh-release@v3`（可变主版本 tag），release 资产/tag 由第三方 Action 创建。
- **改动**：未改代码；建议把 Action pin 到完整 commit SHA，并用 Dependabot 升级。
- **文件**：—（报告引用 `.github/workflows/build-unsigned.yml`）
- **提交**：—
- **验证**：读 352-358、544-549，确认权限与 Action 引用；静态核对，未运行 CI。
- **手测**：把 Action 固定到 SHA 后运行 tag 发布，确认 Release 资产正常且 workflow diff 不再出现 `@v3`。
- **风险/遗留**：第三方 Action tag 被移动或仓库被入侵时，可在持有 write token 的 job 中替换发布产物。

### F21 暂缓

- **结论**：MARKETING_VERSION 2.0 与构建号编码出的 1.4.1 并存属实，但 pbxproj 禁止编辑，未改代码。
- **原因**：`project.pbxproj:678` 的 `CURRENT_PROJECT_VERSION = 9110401`，而 `AppVersion.releaseVersion` 按 91 前缀解码得到 1.4.1（AppVersion.swift:38-54）；同一 target 的 `MARKETING_VERSION = 2.0`（694 行），About 页显示 1.4.1，系统/App Store 显示 2.0。
- **改动**：未改代码；建议由单一来源（xcconfig）派生 MARKETING_VERSION 与构建号，并让发版 tag 与 MARKETING_VERSION 一致。
- **文件**：—（报告引用 `MeloX.xcodeproj/project.pbxproj`、`MeloX/Core/App/AppVersion.swift`）
- **提交**：—
- **验证**：读 pbxproj 678/694 与 AppVersion 38-54、66-81，确认解码结果为 1.4.1、CI tag 校验使用 `v<major>.<minor>.<patch>`；静态核对，未编译。
- **手测**：构建后同时查看 About 页、系统 App 信息、App Store Connect 版本和 release tag，确认四者一致。
- **风险/遗留**：对外出现两个版本号，用户报障/更新提示/tag 容易混淆。

### F22 暂缓

- **结论**：执行 PR 代码的构建作业保留 checkout 凭据属实，但工作流禁止编辑，未改代码。
- **原因**：`build-unsigned.yml:106-109` 的 build job checkout 没有 `persist-credentials: false`，而后续执行 PR 分支里的 `build_ios_unsigned.sh`；对比 `unsigned-ios-ipa.yml:30` 已关闭。
- **改动**：未改代码；建议在 build job 的 checkout 加 `with: persist-credentials: false`，并只在需要推送的步骤使用单独 token。
- **文件**：—（报告引用 `.github/workflows/build-unsigned.yml`、`.github/workflows/unsigned-ios-ipa.yml`）
- **提交**：—
- **验证**：读 100-110 与 `unsigned-ios-ipa.yml` 的 checkout 配置差异；静态核对，未运行 CI。
- **手测**：开一个同仓库 PR，在构建脚本中尝试读取 .git/config，确认没有 token；需要推送的 job 单独配置凭据。
- **风险/遗留**：PR 代码可直接读取 `.git/config` 中的持久化 token；当前权限为 `contents: read`，但权限提升或私有 fork 时会放大。

### B13 暂缓

- **结论**：macOS target 仍保留旧的一起听协议实现，两端同房间时 macOS 仍可能重放自身命令回声，未改代码。
- **原因**：iOS 侧已用 `playerTransportDidChange` + `pendingTransportReport` 重试 + clientSeq 回声抑制；`MeloXDesktop` 同名文件仍是 `playerSongDidChange/playerPlaybackDidChange/playerDidSeek` + `shouldReportLocalChanges/suppressReportsUntil` + `reportLocalCommand`，Synchronization 也是旧版。
- **改动**：未改代码；移植 iOS 协议需要同步修改 PlayerEvents、Synchronization、Store 状态和 PlayerStore 调用点，属大范围跨端重构，无编译器无法保证 Session/Queue/播放器事件签名一致。
- **文件**：—（报告引用 `MeloX/Core/Playback/Session/ListenTogetherStore+PlayerEvents.swift` 与 `MeloXDesktop` 同名文件）
- **提交**：—
- **验证**：读两端 `ListenTogetherStore+PlayerEvents.swift` 全文，确认接口与重试/回声抑制实现不同、Desktop Synchronization 为旧版；静态核对，未编译。
- **手测**：iOS 与 macOS 同时进入同一 Listen Together 房间，在 mac 端点暂停/切歌/拖动，观察是否被自身命令回声弹回；修复后应只应用远端命令。
- **风险/遗留**：不修则 macOS 在共同房间仍可能出现 seek 回退/自我覆盖；直接移植若遗漏 macOS PlayerStore 调用点可能编译失败或同步更差。

## 5.8 b8-arch（31 条）

### D2 暂缓

- **结论**：PlayerStore 仍是 2014 行、承载十余项职责的上帝对象；拆分需新增源文件与 target 成员，未改代码。
- **原因**：单一 `@MainActor @Observable` 类（38-40 行），整文件 2014 行且无 extension；init（276-324）内直接构造 AudioPlaybackEngine、AutoMixAudioAnalyzer、NowPlayingSession、LyricsLiveActivityController、PlaybackSleepTimer，队列/传输/持久化/历史/NowPlaying/ActivityKit/一起听/睡眠/AutoMix 全耦合。
- **改动**：未改；拆分需新增源文件并改 target 成员（本批禁止），本批只在该文件完成 D27 的无风险重命名。
- **文件**：`MeloX/Core/Playback/Session/PlayerStore.swift`
- **提交**：—
- **验证**：读 1-340 与 1080-1339，确认无 extension、依赖在 init 内 new、房间闭包在 113-117 行；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是拆成 QueueController/PlaybackTransport/NowPlayingPublisher/ListenTogetherBridge/PlaybackRestoreService 等并调整工程文件。

### D3 暂缓

- **结论**：AppSettings 2120 行、上百个 UserDefaults 属性手写读写，拆分需多个新设置文件，未改代码。
- **原因**：单类 2120 行，`Key` 枚举在 114 行，`init(defaults:)` 在 1312 行逐个读取全部 key；每个偏好都是 `var + didSet` 手写 defaults。
- **改动**：未改；按域拆 PlaybackPreferences/LyricsPreferences 等并引入 `@DefaultsBacked` 需要多个新设置文件与统一存储层，超出本批可安全修改范围。
- **文件**：`MeloX/Core/Settings/Application/AppSettings.swift`
- **提交**：—
- **验证**：读 1-140 并 grep `Key`/init 定位 114/1312，确认 MeloX 内有 14 个 `private enum Key`；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是设置分层 + 统一默认值存储层。

### D4 暂缓

- **结论**：MeloXDesktop 复制了约 2k 行 AppSettings 并共用同一批 UserDefaults key，抽共享层需改 pbxproj，未改代码。
- **原因**：Desktop `AppSettings.swift:126` 的 `hasCompletedOnboarding` 与 iOS `AppSettings.swift:115` 使用同一个字符串 `melox.hasCompletedOnboarding`；两份文件各自维护约 2k 行读取、默认值与规范化逻辑。
- **改动**：未改；抽 `MeloXSettingsCore` 需要把共享文件加入两个 target，必须编辑 project.pbxproj（本批禁止）。
- **文件**：`MeloXDesktop/Core/Settings/Application/AppSettings.swift`、`MeloX/Core/Settings/Application/AppSettings.swift`
- **提交**：—
- **验证**：读 Desktop 100-139 与 iOS 114-119 确认同 key；读 pbxproj 257-262/311-314，确认 Desktop synchronized groups 只有 MeloXDesktop 与 MeloXLocalization；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是共享设置核心 + 工程文件调整。

### D5 暂缓

- **结论**：MusicQuality 在 iOS、Desktop、Watch 有三份实现属实，但统一需改工程文件并设计 Watch 迁移，未改代码。
- **原因**：iOS 与 Desktop 的 `MusicQuality` 逐字相同（7 个 case，rawValue 为 128000 到 jymaster）；Watch 的 `WatchStreamingQuality` 同样 7 个 case，但 rawValue 是 `standard` 等 case 名，与 iOS 的数值型 rawValue 不同。
- **改动**：未改；共享需要移动文件成员或修改 pbxproj；Watch 端 rawValue 不同，统一前必须设计 UserDefaults 迁移。
- **文件**：`MeloX/Core/Settings/Playback/MusicQuality.swift`、`MeloXDesktop/Core/Settings/Playback/MusicQuality.swift`、`MeloXWatch/Settings/WatchPreferenceKeys.swift`
- **提交**：—
- **验证**：对比三份文件全文，确认 apiLevel/title 映射重复、Watch 无显式数值 rawValue；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是共享枚举 + Watch rawValue 迁移方案。

### D6 暂缓

- **结论**：MeloXLiveActivityShared 未加入 Desktop target、导致共享类型被复制属实，修复必须改 pbxproj，未改代码。
- **原因**：iOS target 的 `fileSystemSynchronizedGroups` 包含 `C2283E4B5CA041B19C10CB23`（MeloXLiveActivityShared，pbxproj 257-262）；Desktop target 只有 `D30000000000000000000003` 与 `E40000000000000000000001`（311-314），因此 Desktop 复制了 `LyricsLiveActivityArtworkPolicy`。
- **改动**：未改；修法必须把共享组加入 Desktop target，即编辑 project.pbxproj（禁止），也不能在 Desktop 新增共享文件。
- **文件**：`MeloX.xcodeproj/project.pbxproj`、`MeloXDesktop/Core/LiveActivity/LyricsLiveActivityArtworkPolicy.swift`
- **提交**：—
- **验证**：读 pbxproj 240-323，确认 Desktop 未挂载共享组；报告已比对两端 policy 文件 89% 标识符一致；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是工程 target 成员调整。

### D7 暂缓

- **结论**：NowPlayingView 单 View 1015 行、在视图里改设置并跑节拍分析属实，抽离需新文件/大规模重排，未改代码。
- **原因**：仍是单 View；158-160 行 `.task(id: beatAnalysisTaskID)` 调 `loadBeatTimeline`，216-228 行在 `onChange(page)` 中直接写 `settings.rememberedNowPlayingPage`，body 还挂多个 task/onChange 与多套布局分派。
- **改动**：未改；抽 `NowPlayingChromeState` 并把节拍分析移出 View 需要新文件或大规模重排 View，且无法验证 SwiftUI diff。
- **文件**：`MeloX/Features/Player/NowPlaying/NowPlayingView.swift`
- **提交**：—
- **验证**：读 140-239，确认页面偏好写入与节拍任务仍在 View 内；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是 View 状态与副作用抽离。

### D8 暂缓

- **结论**：AppleMusicLyricsView 3699 行、SynchronizedLyricText 983 行的巨型 View 属实，拆分需多个新文件，未改代码。
- **原因**：AppleMusicLyricsView 单 struct 从第 4 行延续到文件末（共 3699 行）；SynchronizedLyricText 从 `Shared/SynchronizedLyricText.swift:53` 起（约 983 行），布局、行级动画、焦点级联、保留视口与叠加层都在超大类型内。
- **改动**：未改；拆 LyricsViewportLayout、LyricRow、LyricCascadeCoordinator、LyricOverlay 需要新增多个文件并移动私有成员。
- **文件**：`MeloX/Features/Player/Lyrics/AppleMusic/AppleMusicLyricsView.swift`、`MeloX/Features/Player/Lyrics/Shared/SynchronizedLyricText.swift`
- **提交**：—
- **验证**：读 AppleMusicLyricsView 头尾（尾行为 3699）与 SynchronizedLyricText:53，确认类型规模；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是歌词视图分层与状态归属重排。

### D9 暂缓

- **结论**：TrackRowView 与 PlaylistTrackList 各自实现一套歌曲菜单与 sheet 路由属实，抽共享组件需新文件，未改代码。
- **原因**：TrackRowView 用 `.contextMenu` 实现播放下一首、收藏、下载/删除、信息、评论、分享；PlaylistTrackList 的私有行又用 `Menu` 实现同一组操作，并各自定义 `TrackRowSheet` 与 `PlaylistSongSheet`，sheet 分发与 `presentationDetents` 几乎相同。
- **改动**：未改；抽 `SongActionsMenu` 与共享 `SongSheetRoute` 需要新的共享组件文件并重新设计两套菜单接口，且会改变交互。
- **文件**：`MeloX/Shared/Media/TrackRowView.swift`、`MeloX/Features/Playlist/PlaylistTrackList.swift`
- **提交**：—
- **验证**：读 TrackRowView 全文与 PlaylistTrackList 90-400，确认两套动作/枚举独立；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是菜单/路由组件合并 + 交互验收。

### D10 暂缓

- **结论**：TrackRowView 已适配大字号、PlaylistTrackList 私有行仍是固定 HStack 属实，改布局需重排内容，未改代码。
- **原因**：`PlaylistTrackRow` 的 body 仍是固定 `HStack(spacing:4)` 与内层 `HStack(spacing:12)`，文件内无 `dynamicTypeSize/AnyLayout/ScaledMetric`；而 TrackRowView 已用 AnyLayout 在辅助功能字号下纵向重排。
- **改动**：未改；只把内层 HStack 换成 AnyLayout 会让下载勾选、收藏心形、封面各占一行，需要重排内容并真机验收；报告建议的 `TrackRowContent` 复用是更大抽取。
- **文件**：`MeloX/Features/Playlist/PlaylistTrackList.swift`、`MeloX/Shared/Media/TrackRowView.swift`
- **提交**：—
- **验证**：读 PlaylistTrackList 90-260 与 TrackRowView 18-26 对比，确认无大字号分支；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是行内容重排 + 无障碍字号真机验收。

### D11 暂缓

- **结论**：专辑/歌单详情页复制相同的平板背景、调色板与下载回调属实，抽公共件涉及两个大 View 的 API 变更，未改代码。
- **原因**：`AlbumDetailView:194-208` 与 `PlaylistDetailView:299-313` 的 `usesTabletBackdrop/resolvedPalette/usesLightAppearance` 逐字相同；下载工具条与 `startDownloadAll/startSelectedDownloads` 分别在 Album 310-345 与 Playlist 434-469 复制，仅集合类型不同。
- **改动**：未改；抽 `ArtworkDetailPaletteResolver` 与 `MusicCollectionDownloadActions` 涉及两个大 View 的依赖与 API 变更，回归风险高。
- **文件**：`MeloX/Features/Album/AlbumDetailView.swift`、`MeloX/Features/Playlist/PlaylistDetailView.swift`
- **提交**：—
- **验证**：读两文件对应区域，确认复制关系与仅集合参数差异；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是公共调色板解析器 + 下载动作组件抽取。

### D12 暂缓

- **结论**：竖屏/横屏/平板各写一遍歌词页与队列页 presentation 装配属实，抽 stage 需重构三套布局输入，未改代码。
- **原因**：NowPlayingView 的 queue/lyrics presentation 与 `NowPlayingLandscapeView:238-266`、`Tablet/NowPlayingTabletPanels:21-59` 重复装配同一组 `visualState/opacityTransition/spatialTransition/opacitySpec/presentationScale` 参数，仅 presentation 与 resident state 计算不同。
- **改动**：未改；抽 `NowPlayingLyricsStage/QueueStage` 需要重构三套布局的输入与状态计算，无法在本环境验证动画一致性。
- **文件**：`MeloX/Features/Player/NowPlaying/NowPlayingView.swift`、`MeloX/Features/Player/NowPlaying/NowPlayingLandscapeView.swift`、`MeloX/Features/Player/NowPlaying/Tablet/NowPlayingTabletPanels.swift`
- **提交**：—
- **验证**：读 NowPlayingLandscapeView 232-271 与 TabletPanels 19-64，确认参数块重复；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是三套布局统一到共享 stage 并做动画回归。

### D13 暂缓

- **结论**：iPad 侧栏在 View 内拼装业务数据并用 Nuke/UIKit 直接渲染缩略图属实，迁移会破坏 Python 源码切片测试，未改代码。
- **原因**：`ContentView.sidebarPlaylists`（456-475）在 View 内合成 liked playlist、去重并硬截断 40；`loadSidebarArtwork`（488-507）直接用 Nuke `ImagePipeline` 与 `UIGraphicsImageRenderer` 渲染缩略图，绕过统一 Artwork 管线。
- **改动**：未改；移到 LibraryStore 会破坏 `Tools/Tests/test_sidebar_playlists.py:65` 对 `private var sidebarPlaylists:` 的源码切片（脚本会抛 ValueError）；图片管线统一还需另做 Artwork pipeline 改造。
- **文件**：`MeloX/App/ContentView.swift`、`Tools/Tests/test_sidebar_playlists.py`
- **提交**：—
- **验证**：读 ContentView 440-515 与 test_sidebar_playlists.py 50-66，确认脚本直接提取该私有属性；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是业务数据下沉 + 图片管线统一 + 同步更新 Python 切片契约。

### D14 暂缓

- **结论**：28 个 Feature View 直接注入 NeteaseAPI 并自行管理请求/分页/错误属实，建 Store 属大规模重构，未改代码。
- **原因**：grep `@Environment(NeteaseAPI.self)` 在 `MeloX/Features` 命中 28 个文件；`AlbumDetailView.load`（379-405）在 View 内请求 album，并用 `try?` 吞掉 `albumSubscriptionStatus` 失败；评论分页、播客加载等也在各 View 内。
- **改动**：未改；为 28 个页面建立 AlbumDetailModel/SongCommentsModel 等 `@Observable` Store 是新文件与大规模重构。
- **文件**：`MeloX/Features/Album/AlbumDetailView.swift`、`MeloX/Features/Song/SongCommentsView.swift`、`MeloX/Features/Podcasts/PodcastHomeView.swift`
- **提交**：—
- **验证**：grep 计数 28；读 AlbumDetailView 379-405 确认 `try?` 吞错、PodcastHomeView 1-35 确认 View 自持状态；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是逐页引入 Model/Store 层。

### D16 暂缓

- **结论**：多个 View 直接调用 ArtworkAccentColorProvider.shared、缺少注入缝属实，改协议注入跨所有详情页，未改代码。
- **原因**：`ArtworkAccentColorProvider` 仍以 `actor static shared`（75-76）暴露；`AlbumDetailView:123`、`PlaylistDetailView:201`、`AccountHomeView:105`、`PodcastDetailView:105`、`MusicNavigationTransitions:66`、`SkylineLyricsView:46` 等直接访问，View 无注入缝。
- **改动**：未改；把 `ArtworkPaletteProviding` 注入 Environment 是跨所有详情页的协议改造，且需要 composition root 支持。
- **文件**：`MeloX/Core/Artwork/ArtworkAccentColorProvider.swift`
- **提交**：—
- **验证**：grep `ArtworkAccentColorProvider.shared` 确认调用点；读 provider 60-130 确认单例；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是协议 + Environment 注入 + composition root 装配。

### D17 暂缓（部分已修复）

- **结论**：录音器与指纹生成器已改为协议注入，但 Store 生命周期仍跟随 View，未达到报告期望的 Environment 注入。
- **原因**：`SongRecognitionStore` 的 recorder/fingerprintGenerator 原为 `private let` 直接 new 具体类型（原 40-45 行），View 用 `@State private var recognition = SongRecognitionStore()` 持有，依赖不可替换、Store 随 View 重建。
- **改动**：新增 `@MainActor` 协议 `SongRecognitionRecording`（start/snapshot/prepareForConcurrentPlayback/cancel/stop）与 `AudioFingerprintGenerating`（generate），让两个实现类型显式 conform；Store 属性改为 `any` 协议类型，并新增 `init()` 与 `init(recorder:fingerprintGenerator:)` 注入入口；View 生命周期未动。
- **文件**：`MeloX/Features/SongRecognition/SongRecognitionAudioRecorder.swift`、`MeloX/Features/SongRecognition/NeteaseAudioFingerprintGenerator.swift`、`MeloX/Features/SongRecognition/SongRecognitionStore.swift`
- **提交**：`31830a7`
- **验证**：逐一比对协议要求与实现签名（Recorder 73/170/213/217/221，Generator 36）；`SongRecognitionView:13` 仍调用无参 init，grep 确认无其他调用方；静态核对，未编译。
- **手测**：进入听歌识曲，执行一次单次识别和连续识别并取消，确认行为与之前一致。
- **风险/遗留**：协议签名与 `@MainActor` 隔离已核对；剩余工作是 Store 上移到 Environment/App 级，避免随 View 重建。

### D18 暂缓

- **结论**：工程没有测试 target、8 个检查文件不进 Xcode 也不进覆盖率属实，新增 target 需改 pbxproj 与 CI，未改代码。
- **原因**：pbxproj 四个 target 的 productType 只有 application 与 app-extension（240-323），没有 unit-test target；CI 只在 `unsigned-ios-ipa.yml` 用 swiftc 单独编译 Artwork 检查。
- **改动**：未改；新增 `MeloXTests` 与 TEST_HOST 必须编辑 project.pbxproj，CI 增加 `xcodebuild test` 需编辑 `.github/` workflows，两者本批禁止。
- **文件**：`MeloX.xcodeproj/project.pbxproj`
- **提交**：—
- **验证**：读 pbxproj 240-323，未发现 XCTest/TEST_HOST/BUNDLE_LOADER；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是新增测试 target + CI 测试步骤。

### D19 暂缓

- **结论**：回归"测试"从源码抽取方法并与手写假 Store 一起编译属实，迁移到 XCTest 依赖 D18，未改代码。
- **原因**：`test_playback_song_switch.py:58-124` 自带假 Store，172-183 从生产源码切片 `loadCurrentSong` 等方法注入 STUBS；`test_sidebar_playlists.py:64-66` 同样切片 `private var sidebarPlaylists:`；生产 PlayerStore 的多数逻辑并未执行。
- **改动**：未改；迁移到 XCTest 依赖 D18 的测试 target（工程文件改动，禁止）；本批保留被切片的方法名与 `sidebarPlaylists` 属性名，避免 Python 脚本失效。
- **文件**：`Tools/Tests/test_playback_song_switch.py`、`Tools/Tests/test_sidebar_playlists.py`
- **提交**：—
- **验证**：读 test_playback_song_switch.py 50-194 与 test_sidebar_playlists.py 50-66；静态核对，未运行。
- **风险/遗留**：未改动；剩余工作是建测试 target 并把源码切片脚本迁成 XCTest。

### D22 已修复

- **结论**：歌词聚合不再把 6 个来源错误压成一个 noLyrics，改为按来源记录日志。
- **原因**：`LyricsService.load` 原有 6 处 `try?`（自动与指定偏好下的 NetEase、AMLL、QQ Music），任何超时、坏数据或解析失败都被折叠成 nil，最后统一抛 `LyricSourceError.noLyrics`。
- **改动**：新增 `nonisolated private static OSLog Logger`（category LyricsService）；六处 fetch 改为 do/catch，`CancellationError` 保持取消语义，其余错误按来源 `logger.error`；最终无结果时记录聚合日志后再抛 noLyrics。
- **文件**：`MeloX/Core/Lyrics/LyricsService.swift`
- **提交**：`82a8047`
- **验证**：重读 1-222，确认文件中已无 `try?`、任务组仍返回 `FetchEvent?`、publish/merge 流程未改；静态核对，未编译。
- **手测**：断网或屏蔽 AMLL 域名后打开歌词页，用 Console.app 过滤 category `LyricsService`，应看到具体来源失败；UI 仍走 noLyrics 兜底。
- **风险/遗留**：低；仅新增日志，OSLog 插值在 iOS 26 target 可用。

### D23 暂缓

- **结论**：用 Environment 传 Binding、让子页面反向写父页面 tab chrome 状态属实，改数据流 UI 回归风险高，未改代码。
- **原因**：`MusicCollectionTheme.swift:55-77` 通过 `@Entry var tabletCollectionChrome: Binding<TabletCollectionChrome?>?` 让后代 View 直接写 ContentView 的 per-tab 字典，并用 UUID 守卫 onAppear/onChange/onDisappear。
- **改动**：未改；改 PreferenceKey 或让 ContentView 从路由/Store 查询需要重排详情页 chrome 数据流。
- **文件**：`MeloX/Shared/Media/MusicCollectionTheme.swift`、`MeloX/App/ContentView.swift`
- **提交**：—
- **验证**：读 MusicCollectionTheme 全文与 ContentView 中 `tabletCollectionChrome` 的 per-tab Binding；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是 chrome 状态改单向数据流并做 UI 回归。

### D24 已修复

- **结论**：NowPlayingTabletLayout 的裸数字提取为命名常量，运算顺序不变。
- **原因**：`fillsRegion` 与默认分支共用裸数字 320/102/600/168/768/1200，宽度上限分别是 `viewport.width-48` 与 `viewport.width*0.5-40`，语义靠注释隐含。
- **改动**：提取 `playerWidthGrowthStartHeight`、`playerWidthGrowthHeightRange`、`basePlayerWidth`、`playerWidthGrowth`、`elementScaleReferenceHeight`、`elementScaleReferenceWidth`、`splitViewWidthRatio`、`splitViewHorizontalInset`、`filledRegionHorizontalInset`，新增 `scaledPlayerWidth`；两个分支使用命名上限。
- **文件**：`MeloX/Features/Player/NowPlaying/Tablet/NowPlayingTabletLayout.swift`
- **提交**：`56d179a`
- **验证**：重读 1-124，逐项核对公式等价：fills 为 `max(min(scaled, w-48), 1)`、split 为 `min(scaled, w*0.5-40)`；静态核对，未编译。
- **手测**：iPad 全屏、分屏与旋转，确认播放器列宽、面板起始位置与改动前一致。
- **风险/遗留**：无行为变化，纯常量提取；tree-sitter 对新增多行前导 `*` 报 1 条语法诊断（与基线同类写法一致，属分析器限制）。

### D25 暂缓

- **结论**：PlayerStore 与 ListenTogetherStore 通过可变闭包双向耦合属实，改协议 delegate/AsyncStream 需编译与并发验证，未改代码。
- **原因**：`ListenTogetherStore.init`（164-172）给 PlayerStore 的两个 `@ObservationIgnored` 闭包赋值；`PlayerStore.swift:113-117` 声明 `onListenTogetherTransport/onListenTogetherQueueEdit`，重复构造会覆盖回调。
- **改动**：未改；改成协议 delegate 或 AsyncStream 会改动播放与房间同步的调用链。
- **文件**：`MeloX/Core/Playback/Session/ListenTogetherStore.swift`、`MeloX/Core/Playback/Session/PlayerStore.swift`
- **提交**：—
- **验证**：读 ListenTogetherStore 150-180 与 PlayerStore 112-118；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是定义单向事件接口并替换闭包赋值。

### D26 暂缓

- **结论**：偏好 key 分散在 14 个 `private enum Key` 且命名规范不统一属实，统一注册表属高风险迁移，未改代码。
- **原因**：MeloX 内 grep 到 14 个 `private enum Key`；`AppSettings:114-119` 同时有 `melox.` 前缀、裸 camelCase（`musicCookie/playerVolumeControlMode`），init 还直接读 legacy 字面量。
- **改动**：未改；统一 `AppDefaultsKeys` 注册表与 legacy 迁移会触碰所有设置子 store 和存储 key。
- **文件**：`MeloX/Core/Settings/Application/AppSettings.swift`
- **提交**：—
- **验证**：grep 计数 14；读 114-119；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是 key 注册表 + 迁移脚本 + 回滚方案。

### D27 已修复

- **结论**：`listenTogetherRandomSongIDs` 更名为 `listenTogetherPublishedSongIDs`，名字不再暗示随机顺序。
- **原因**：`PlayerStore.listenTogetherRandomSongIDs`（原 106-114）直接返回 `listenTogetherDisplaySongIDs`，名字却暗示 shuffle 排列；唯一调用方 `sendPlaylistSnapshot` 把两者分别作为 `randomSongIDs` 与 `displaySongIDs` 上报。
- **改动**：重命名为 `listenTogetherPublishedSongIDs` 并更新唯一调用点；协议字段 `randomSongIDs` 保持不变，`sendPlaylistSnapshot` 内局部变量改为 `publishedSongIDs`。
- **文件**：`MeloX/Core/Playback/Session/PlayerStore.swift`、`MeloX/Core/Playback/Session/ListenTogetherStore+PlayerEvents.swift`
- **提交**：`220e7b4`
- **验证**：grep 确认旧名在 `MeloX/` 无残留（Desktop 独立副本未动）、新名仅定义与唯一调用；静态核对，未编译。
- **手测**：创建一起听房间并修改本地队列，确认 playlist 上报成功，抓包 `randomSongIDs` 与 `displaySongIDs` 顺序一致。
- **风险/遗留**：低；内部属性，无跨 target 引用。

### D28 已修复

- **结论**：删除 iOS 侧无调用方的 `topArtists()`、`songURL(id:)` 与对应响应类型。
- **原因**：iOS target 的 `NeteaseAPI.topArtists()`（110-113）与 `songURL(id:)`（526-528）没有调用方；`ArtistToplistResponse/ArtistToplist` 仅服务 `topArtists`。Desktop 有独立同名实现。
- **改动**：删除 iOS 两个方法与两个响应类型；Desktop 文件不动。
- **文件**：`MeloX/Core/Networking/NeteaseAPI.swift`、`MeloX/Core/Models/Networking/APIResponses.swift`
- **提交**：`66ffb04`
- **验证**：grep 全仓确认 `MeloX/` 内无 `api.topArtists()`/`api.songURL(` 调用与类型引用，Tools 也无；Desktop 的 `topArtists` 由 `DesktopHomeStore:56` 使用，保留；静态核对，未编译。
- **手测**：构建 iOS；macOS 首页热门歌手仍走 Desktop 自己的 NeteaseAPI。
- **风险/遗留**：低；若后续 iOS 需要这些接口需重新添加。

### D29 已修复

- **结论**：删除无读取方的 `dampingRatio`、`undampedPeriod` 与 `forcedLineCatchUpSpring`。
- **原因**：`dampingRatio/undampedPeriod` 只有定义无读取；`forcedLineCatchUpSpring` 只有字段声明与 iOS26_6 初始化参数，无任何消费者。
- **改动**：删除两个计算属性、`forcedLineCatchUpSpring` 字段、注释与初始化参数；`AppleMusicLyricsDynamicSpring` 内的同名局部变量未动。
- **文件**：`MeloX/Core/Lyrics/LyricPhysicalSpringParameters.swift`、`MeloX/Core/Lyrics/AppleMusicLyricsMotionProfile.swift`
- **提交**：`6895b7e`
- **验证**：grep 全仓确认无读取；该结构体只在本文件 iOS26_6 中初始化，参数已同步删除；静态核对，未编译。
- **手测**：播放 Apple Music 风格歌词，确认焦点与行切换弹簧动画与改动前一致。
- **风险/遗留**：低；删除未使用 API。

### D30 暂缓

- **结论**：Core/System 反向依赖 SwiftUI/UIKit 并定义 View modifier 属实，拆分需新文件或平台协议，未改代码。
- **原因**：`ScreenAwakeCoordinator.swift` 同时 `import SwiftUI/UIKit`，包含计数逻辑、`View` extension 与 `UIApplication.shared.isIdleTimerDisabled` 全局副作用。
- **改动**：未改；把 ViewModifier 移到 Features/Shared 需要新文件；把 UIApplication 抽成协议又需要平台实现与 composition root。
- **文件**：`MeloX/Core/System/ScreenAwakeCoordinator.swift`
- **提交**：—
- **验证**：读全文 1-75，确认 `extension View` 与 UIApplication 调用；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是分层拆分 + 平台协议注入。

### D31 暂缓

- **结论**：同一个播放失败 alert 的 Binding 样板复制到多个页面属实，抽 modifier 需新共享 UI 文件，未改代码。
- **原因**：`PlaylistDetailView:262-278` 与 `LibrarySongsView:138-154` 的 `playbackErrorMessage` alert Binding、OK 按钮与文案回退逐字相同，仅 fallback 文案不同。
- **改动**：未改；抽 errorAlert modifier 需要新的共享 UI 文件（禁止新增源文件），放进现有无关组件文件又会造成分层问题。
- **文件**：`MeloX/Features/Playlist/PlaylistDetailView.swift`、`MeloX/Features/Library/LibrarySongsView.swift`
- **提交**：—
- **验证**：读两处 alert 代码，确认绑定与按钮逻辑重复；静态核对，未编译。
- **风险/遗留**：未改动；剩余工作是新增共享 alert modifier 文件并替换调用点。

### D32 已修复

- **结论**：音乐集合平板布局的全局常量与比例魔法数集中到 `MusicCollectionLayout`，数值未变。
- **原因**：`musicCollectionWideInset` 是 `PlaylistDetailContent.swift:4` 的顶层全局常量，被 `PlaylistTrackList` 跨文件使用；0.28/300/0.24/220/710 等布局数字散落在 View body 中无名称。
- **改动**：在 `Shared/Media/MediaCardGridLayout.swift` 新增 `MusicCollectionLayout`（wideInset、wideLayoutBreakpoint、heroArtworkRatio、maximumHeroArtworkSize、trackArtistColumnRatio、maximumTrackArtistColumnWidth）；`PlaylistDetailContent` 删除全局常量并改用 token，`PlaylistTrackList` 同步替换。
- **文件**：`MeloX/Shared/Media/MediaCardGridLayout.swift`、`MeloX/Features/Playlist/PlaylistDetailContent.swift`、`MeloX/Features/Playlist/PlaylistTrackList.swift`
- **提交**：`956ead6`
- **验证**：grep 全 `MeloX/` 确认 `musicCollectionWideInset` 无残留、`MusicCollectionLayout` 仅一处定义；读改动区确认数值未变；静态核对，未编译。
- **手测**：iPad 歌单页在 710pt 附近缩放，确认宽布局切换、hero 封面最大 300pt、艺术家列最大 220pt 与改动前一致。
- **风险/遗留**：低；同 target 内部类型，无命名冲突。

### E17 暂缓（确认亮点，无需修改）

- **结论**：TrackRowView 在辅助功能字号下重排为纵向布局并把序号读给 VoiceOver，是确认亮点，无需修改。
- **原因**：`TrackRowView.swift:19-26` 已用 `dynamicTypeSize.isAccessibilitySize` 与 `AnyLayout` 在辅助功能字号下纵向布局，并用 `@ScaledMetric` 控制序号宽度；219-221 将序号并入 VoiceOver 文本。
- **改动**：无需修改。
- **文件**：`MeloX/Shared/Media/TrackRowView.swift`
- **提交**：—
- **验证**：读 18-26、95-110、210-225，确认实现与报告一致；静态核对，未编译。
- **风险/遗留**：无。

### E18 暂缓（确认亮点，无需修改）

- **结论**：FilterPicker 统一 44pt 最小高度并在辅助功能字号下自动切菜单，是确认亮点，无需修改。
- **原因**：`FilterPicker.swift:12-25` 在 `usesMenu` 或辅助功能字号时切 `.menu`，否则 segmented 并限制 `maximumWidth`，同时 `.frame(minHeight: 44)`。
- **改动**：无需修改。
- **文件**：`MeloX/Shared/Components/FilterPicker.swift`
- **提交**：—
- **验证**：读全文，确认逻辑与报告一致；静态核对，未编译。
- **风险/遗留**：无。

### E19 暂缓（确认亮点，无需修改）

- **结论**：播客分类网格随 Dynamic Type 缩放列宽、标签在辅助功能字号下换行，是确认亮点，无需修改。
- **原因**：`PodcastHomeView.swift:14-18` 用 `@ScaledMetric categoryMinimumWidth=154` 驱动 adaptive `GridItem`；`PodcastComponents.swift:172-176` 在辅助功能字号下取消 `lineLimit` 并允许纵向扩展。
- **改动**：无需修改。
- **文件**：`MeloX/Features/Podcasts/PodcastHomeView.swift`、`MeloX/Features/Podcasts/PodcastComponents.swift`
- **提交**：—
- **验证**：读 PodcastHomeView 1-35 与 PodcastComponents 165-185，确认实现与报告一致；静态核对，未编译。
- **风险/遗留**：无。

## 6 暂缓项汇总

### 6.1 51 条 deferred 按原因分组

| 原因 | 数量 | ID |
| --- | --- | --- |
| 需要新增源文件或改工程文件（project.pbxproj / target 成员 / 新资源） | 20 | D2、D3、D4、D5、D6、D7、D8、D9、D10、D11、D12、D13、D14、D16、D23、D25、D26、D30、D31、F7 |
| 大规模重构 / 并发隔离，无编译器无法安全验证 | 9 | C0、A11、A13、C5、C9、C10、C11、C16、C18 |
| 产品 / 协议决策（房间模式、推荐刷新、间距 token） | 3 | B0、C19、E15 |
| 安全凭据迁移（Keychain、手表 token） | 3 | F0、F1、F2 |
| CI / 构建脚本 / 签名 / 版本（`.github`、pbxproj、脚本禁止编辑） | 11 | F8、F9、F10、F11、F15、F16、F17、F18、F19、F21、F22 |
| 跨平台移植（macOS 一起听副本） | 1 | B13 |
| 测试基础设施（依赖测试 target） | 2 | D18、D19 |
| 独立增强 / 性能优化，收益需实测 | 2 | A21、C23 |

### 6.2 10 条 partially_fixed 与剩余工作（含复核降级 C15）

| ID | 已完成 | 剩余工作 |
| --- | --- | --- |
| B1 | 首次观察到实际应用之间的耗时补偿 | 协议层命令时间戳（或可靠 heartbeat timeSpan 校正），覆盖首次观察前的 age |
| C3 | Apple Music 背景 120fps → 60fps | 真机评估 `maxSampleOffset` 与 `drawingGroup`，确认无边缘采样错误/合成变化 |
| D15 | 首页 fallback 7 处 `try?` 改为 do/catch + OSLog | UI 错误通道、失败时保留上次缓存 |
| C7 | `position()` filter+map+Set 合并为一次遍历 | 降低前缀扫描成本（可重叠行集合缓存） |
| C12 | 文字缓存 FIFO → LRU | Key 改为 lineID + 内容修订号，避免整段音节哈希 |
| C14 | 每次 draw 只构建一次 reveal Gradient | 发光模糊图层缓存 |
| C15 | composition 移出子视图 GeometryReader，按 View 值 init 计算 | 按 text/seed/sequence 持久缓存，避免父级 GeometryReader/父 body 重建时重新计算 |
| C26 | 行 `onDisappear` 停止无限位移动画 | 传入 `isPlaying/scenePhase`，在暂停/后台时也停止 |
| C28 | 缩略图尺寸乘 `displayScale` | 去掉内层 GeometryReader，由父布局传确定尺寸 |
| D17 | 录音器/指纹器协议注入 | Store 生命周期上移（Environment / App 级），不再随 View 重建 |

## 7 已知编译与设备风险

- **没有任何编译证据**：全仓没有 Swift/Xcode 工具链；`git diff --check` 只验证空白字符，不代表编译、链接或测试通过。tree-sitter 语法扫描（62 个改动 Swift 文件：基线 33 条诊断、pipeline 35 条）只作参考——新增的 2 条是 D24 多行前导 `*` 运算符，与基线既有同类写法一致，属语法分析器限制，**不是已确认的编译错误**。
- **没有运行证据**：未跑任何测试、未启动 App、未做真机/模拟器 UI、未做 Instruments 性能测量、未抓包、未跑 CI。
- B12：`@unchecked Sendable` 包装 `UIImage`，并让包含 UIKit 图像的结果字典经过 task group 边界；其实际 Sendable/隔离诊断取决于 SDK 与 Swift 编译设置，并发安全需编译与线程检查器确认。
- C1：可选三元表达式未发现明确语法/类型矛盾；这不代替 Swift 类型检查，不能因缺少编译器就宣称编译通过。
- A5/B4：已核对 `MusicModels.swift:256-272`，占位构造器的其余参数有默认值，调用标签匹配；`Set.subtract` 接受同元素 Sequence。未发现明确签名错误，但仍未进行 Swift 类型检查。
- D21：`QQMusicLyricMatchStore` 的 actor/static 隔离需编译确认。
- F20：`#if DEBUG assertionFailure` 在任一 target/Preview 缺 lproj 时会崩溃（Release 不受影响）。
- A16：新的 `data` 校验对心跳也生效，若服务端心跳成功时返回 `data:null`，会被误判为失败并触发重试/重连。
- B2/B10：对非瞬态的服务端拒绝会以 8s 间隔无限重试（B2 会持续阻塞远端命令应用，B10 会持续阻塞远端队列覆盖）。
- B5：暂停心跳约 10s（原约 5s），若房间服务端超时更短需要回调节奏。
- B6：playMode 映射只覆盖 SINGLE/LOOP，其他模式未验证。
- B1：无法补偿"首次观察之前"已流逝的命令 age。
- B9：`restore()` 在 `hasRestoredPlayback` 时提前返回，可能不会 await 一次进行中的 restore（启动竞态残余）。
- A17：高水位回声抑制假设 `clientSequence` 按账号独立递增；同账号多设备同房间可能误判。
- F5：要求登录 Cookie 的 domain 必须为 `music.163.com`；若服务端把 `MUSIC_U` 写在 `.163.com`，登录会一直等待（风险，非已证实缺陷）。
- F6：NOS LBS 上传地址必须是 `https` 且命中白名单（`127.net/126.net/netease.com/163.com/163yun.com`）；新 CDN 或 IP 会让云盘上传失败，且只校验初始 URL、不校验重定向目标（风险，非已证实缺陷）。
- E1：排行榜封面采用"限制尺寸"替代方案，曲目行仍以 `wideArtistColumnWidth: nil` 走窄行；顶部安全区留白需真机确认。
- E5：窗口宽度低于 618pt 会回退紧凑 MiniPlayerView（558-618pt 区间的体验变化需真机确认）。
- C20：并发请求同一封面时共享首个调用者的 `fallbackPrefersDarkAppearance`。
- C25：`ForEach` 容器身份由 `song.id` 改为 index（行内仍 `.id(song.id)`），插入/删除/重排的滚动与动画需真机确认。
- C15：composition 在 View init 计算，且 `EVALyricsView.swift:53-68` 把它构造在另一层父 GeometryReader 内，父几何失效仍会重建并重跑 init（只移出了子视图自身的 GeometryReader，没有持久缓存）。
- A20：清除 attempt 后没有额外退避闸门，持久性流媒体失败可能形成重试风暴。
- B14：0.5 秒窗口会把窗口内到达的真实中断（来电/Siri）当成自身配置忽略。
- C6/C13：触发键以歌词端点 ID 为主，若中段时长/来源变化而端点不变，可能失去周期兜底。
- D17：Store 生命周期仍跟随 View，注入只解决了依赖替换。
- F8/F21：歌词组件 `CFBundleVersion` 与主 App 不一致（可能 Invalid Bundle）、`MARKETING_VERSION 2.0` 与构建号解码出的 1.4.1 并存（对外两个版本号）。

## 8 建议验证顺序

1. **先构建 iOS（MeloX）target**：优先 `PlayerStore.swift`、`AudioPlaybackEngine.swift`、`AudioPlaybackDeck.swift`、`AudioPlaybackSessionConfigurator.swift`、`ListenTogetherStore*.swift`、`PlaylistDetailContent.swift`、`PlaylistTrackList.swift`、`ContentView.swift`、`ArtworkImage.swift`、`TimedLyricTextBuilder.swift`、`LyricGlowTextRenderer.swift`。
2. **再构建 macOS（MeloXDesktop）**：确认 F5/F6 的双端改动、F13 的 InfoPlist.strings、F1 的 AppSettings 现状；`NeteaseDirectClient`、`DesktopLoginView`。
3. **watch / widget**：MeloXWatch（F23 裸 token 登录、F2 现状）、MeloXLyricsWidget（F8 版本一致性、C2/C21 Live Activity 与封面缓存）。
4. **定向手测（播放/一起听）**：A0（连续识别后会话恢复）、A7（队列播完不重新拉流）、A14（goTo 时机与失败 pause）、B7/B14（中断上报与混音切换）、B2/B10（弱网重试不被旧命令弹回）、B4/B8/B5（房间目标缺失、删歌、轮询节奏）、B9（房间内杀 App 重启）。
5. **定向手测（下载/网络/存储）**：A2（200 HTML/截断文件拒绝）、A3（重复下载原子替换）、A23（强杀后暂存清理）、A15（清理临时文件不删通知附件）、A10/A24（错误不再被伪装）、A25（切号云盘数据）、D20/D21/D22（日志与 QQ 匹配迁移）、F5/F6（Cookie 域、上传白名单）。
6. **定向手测（UI/无障碍）**：E0（跟随系统外观）、E1（iPad 排行榜）、E3/E4/E5/E6/E7/E10/E12/E13/E14/E16/B15/B17 在 iPad 多字号、多外观、Stage Manager 宽度下逐项确认；E17/E18/E19 作亮点回归。
7. **性能**：C1/C2/C4/C22/C6/C13（10Hz 派生路径）、C3（120→60fps）、A9（persist 频率）、A13/C0（主线程数据库/解析）、C16/C18/C28（列表与封面）、B12/C20（封面并发）。
8. **构建/发布检查**：F8/F21（版本一致性）、F7（PrivacyInfo 上传校验 ITMS-91053）、F10（CI 产物）、F19/F22/F9（workflow 安全）。
9. **macOS/watch 联调**：B13（同房间回声）、F3（文案与手表同步一致）、F2（退出登录是否清手表 Cookie 的现有缺口）。

## 9 提交清单

`b59457f` 之后共 55 个提交（按时间从旧到新；短 SHA 与 subject 逐条来自 `git log`）：

| # | SHA | Subject |
| --- | --- | --- |
| 1 | `ebbb733` | fix(recognition): restore playback session after continuous mode (A0) |
| 2 | `36f1e0c` | fix(playback): report session activation failure on resume (A22) |
| 3 | `13c1632` | fix(playback): queue-end and listen-together state (A7,A14,B7,B14) |
| 4 | `1ef4f65` | fix(listen-together): sync queue, progress and polling |
| 5 | `8f548c2` | fix(listen-together): retry reports and harden command echoes |
| 6 | `f5e4080` | fix(listen-together): reject unconfirmed action responses (A16) |
| 7 | `36218a3` | fix(collection): follow system appearance on iPad details (E0) |
| 8 | `911514d` | fix(playlist): iPad collection fixes (B3 E1 E3 E4 E7 E12 B15 E16) |
| 9 | `7c961aa` | fix(mini-player): title width and scalable icons (E5, E13) |
| 10 | `1bc0c53` | fix(search): contrast scrim for category cards (E6) |
| 11 | `a4bedfa` | perf(sidebar): load playlist artwork concurrently (B12) |
| 12 | `8cb0817` | fix(listening-rank): show period description text (B17) |
| 13 | `9f552e7` | fix(now-playing): dim disabled mode buttons (E10) |
| 14 | `06aa68f` | fix(explore): enlarge category pill touch targets (E14) |
| 15 | `be0fcb7` | perf(playback): trim 100ms clock work and persistence (C1, C2, C4, A9) |
| 16 | `6242a88` | perf(now-playing): isolate 10Hz progress reads (C22) |
| 17 | `aa3b4c5` | perf(lyrics): drop 10Hz progress scans in sync views (C6, C13) |
| 18 | `8edce1a` | perf(backdrop): cap Apple Music backdrop at 60 fps (C3) |
| 19 | `156a008` | fix(downloads): skip corrupt records instead of failing library (A1) |
| 20 | `94275bc` | fix(downloads): atomically replace existing audio files (A3) |
| 21 | `fa7c3a7` | fix(downloads): validate payloads before installing downloads (A2) |
| 22 | `0114bec` | fix(downloads): remove orphaned staged transfers at launch (A23) |
| 23 | `bd3cac0` | fix(storage): keep lyrics notification attachments on cleanup (A15) |
| 24 | `851581a` | fix(network): stop masking errors in fallbacks (A10, A24) |
| 25 | `ff03f6a` | fix(cloud): drop stale account responses after switch (A25) |
| 26 | `4556bcc` | fix(automix): retry streaming preparation after failure (A20) |
| 27 | `7329c02` | fix(home): log fallback recommendation failures (D15) |
| 28 | `4fe619b` | fix(storage): log page cache open and IO failures (D20) |
| 29 | `d2b1412` | fix(lyrics): persist QQ matches in Application Support (D21) |
| 30 | `5c5e8a7` | fix(lyrics): disable third-party lyric sources by default (F4) |
| 31 | `479579e` | fix(account): restrict login cookies to music.163.com (F5) |
| 32 | `225b104` | fix(cloud): require HTTPS and trusted NOS upload hosts (F6) |
| 33 | `2940ba3` | fix(l10n): localize macOS audio capture permission prompt (F13) |
| 34 | `ea5936f` | fix(l10n): surface missing localization bundles in debug (F20) |
| 35 | `f46b09b` | fix(watch): recognize bare MUSIC_U tokens as signed in (F23) |
| 36 | `d3ef15f` | fix(l10n): disclose Apple Watch cookie sync in privacy copy (F3) |
| 37 | `82a8047` | fix(lyrics): log per-source lyric fetch failures (D22) |
| 38 | `56d179a` | refactor(nowplaying): name tablet layout metrics (D24) |
| 39 | `956ead6` | refactor(playlist): centralize music collection layout tokens (D32) |
| 40 | `220e7b4` | refactor(listen-together): rename published song IDs (D27) |
| 41 | `66ffb04` | refactor(networking): remove unused iOS API methods (D28) |
| 42 | `6895b7e` | refactor(lyrics): drop unused spring parameters (D29) |
| 43 | `31830a7` | refactor(recognition): inject recorder and fingerprint generator (D17) |
| 44 | `350c745` | perf(lyrics): pause offscreen retained lyric rows (C8) |
| 45 | `05433aa` | perf(lyrics): cache EVA composition per view (C15) |
| 46 | `fdb7c08` | perf(lyrics): stop skyline drift when rows disappear (C26) |
| 47 | `36570c7` | perf(artwork): request thumbnails at display pixel size (C28) |
| 48 | `ea99562` | perf(artwork): coalesce concurrent detail asset loads (C20) |
| 49 | `c6c0697` | perf(lyrics): make timed text cache LRU (C12) |
| 50 | `b624849` | perf(lyrics): build reveal gradients once per draw (C14) |
| 51 | `1031ffa` | perf(library): resolve favorite songs once per body (C17) |
| 52 | `01810aa` | perf(library): resolve download lists once per body (C24) |
| 53 | `ad6173c` | perf(playlist): avoid enumerated array in track list (C25) |
| 54 | `640740f` | perf(lyrics): build active lyric set in one pass (C7) |
| 55 | `6bf8431` | perf(artwork): honor URL cache for artwork downloads (C21) |

- **纠错型提交**：0。本轮没有发现"明确是缺陷、又能在无编译验证下安全修复"的代码问题，因此没有新增代码提交。
- **文档提交**：`65b2336` 为首次 FIXES.md 提交，随后追加本次 C15 状态与证据归因校正；两次均仅改本文，不改源码、不推送。首次需显式 `git add -f FIXES.md`，因为本地 `.git/info/exclude` 列出了它；本轮未改 exclude。

## 10 未做与未验证事项

- **未编译**：没有 Swift 工具链/Xcode，iOS、macOS、watchOS、widget 四个 target 均未构建；未做类型检查、未做链接、未做资源打包。
- **未运行测试**：`.fix/parsecheck.sh`、`Tools/Tests/*.py`、tree-sitter 之外的静态检查、CI workflow 均未执行；`git diff --check` 只是空白检查。
- **未做设备/界面验证**：没有真机或模拟器，未验证 Dynamic Type、辅助功能字号、浅/深色、Stage Manager 宽度、iPad 分屏、旋转、VoiceOver。
- **未做网络/服务端验证**：登录 Cookie 域、NOS 上传白名单、歌词第三方源、一起听服务端 `data:null` 与心跳节奏、云盘切号，全部只有静态推断。
- **未做签名/发布验证**：Keychain、entitlements、App Sandbox、ad-hoc 签名、公证、App Store Connect（ITMS-91053 / Invalid Bundle）均未验证。
- **未做性能测量**：没有 Instruments/Time Profiler，C1/C2/C3/C4/C6/C7/C13/C22、B12/C20、A9 的收益全是静态推断。
- **未同步桌面副本**：MeloXDesktop 下的 `PlayerStore`、`DownloadStore`、`ListenTogetherStore`、`ArtworkDataLoader`、`PageContentCache` 等仍是旧实现（除 F5/F6 双端同步、F3/F4/F13 相关文件）；两端行为差异未验证。
- **未完成剩余 61 条**：51 条 deferred + 10 条 partially_fixed 的剩余工作见第 6 节；另 8 条有意设计/确认亮点不作为已完成修复计数。
- **未验证脚本契约**：D13/D19 依赖 `Tools/Tests/*.py` 对源码的切片（`private var sidebarPlaylists:`、`loadCurrentSong` 等），本轮只保证未改这些名字，未实际运行脚本。
- **提交状态**：本文件在复核结束时本地提交（未推送）；REVIEW.md、`.fix/reports/*`、`.agent-notes.md`、源码、工程文件、CI 均未改动。

## 11 设备反馈第二轮（device round 2）

### 11.1 范围、基线与硬限制

- **基线**：`59cb8ec`（`docs(C15): correct review status and evidence attribution`），分支 `fix/device-round-2`；首轮 10 个代码/测试提交，follow-up 另有 5 个代码/测试提交和 1 个文档提交，均未推送。
- **症状来源**：用户提供的 iPad16,3、iPadOS 27 窗口化 / Stage Manager 实机反馈。**没有 crash log**；提示中的 ca7f/c439/469d 截图在本机附件目录中不存在，本轮只能按文字描述定位，不能声称看过截图。
- **Owner analytics（2026-11-09 补充，来自较旧版本，非本轮构建）**：`moye.MeloX` telemetry 有 Non-Responsive Task Runloop Hang 22–44s 分桶，以及 Extended Launch Runloop Hang 3s、26s 分桶；**没有实际 crash stack**。这加强“主线程阻塞 / 系统 watchdog”假设，但不能证明 resize 崩溃的根因，也不能归因到本分支。
  - 按此线索复核到的现有主线程 I/O：`DownloadStore.init`（`@MainActor`）同步打开/迁移 GRDB、fetch/解码全部下载记录、逐个检查文件并删除缺失记录；`LibraryStore` 启动持久化在 MainActor 取快照，`PageContentCache.store` 也在 MainActor 执行 `JSONEncoder().encode` 后才把 Data 交给 actor。两者都可能是启动/恢复 hang 的来源，但本轮**未改**：缺少编译/真机环境，且改动会触及启动顺序与持久化契约，先记录为后续 focused follow-up。
  - `ArtworkAccentColorProvider` 在本轮之前就是独立 actor + per-URL `assetsCache`；本轮只修查询 key 的 URL 规范化，**没有“首次把取色移出主线程”**。
- **环境**：没有 Xcode、iOS SDK、模拟器或 iPad；只有 Swift 6.3 的 `swift-frontend -parse`（只做语法解析，不导入 SDK、不做类型检查）。因此**本轮所有结论仍是静态核对**。
- **未改动**：`.fix/`、REVIEW.md、工程文件、CI/workflows、签名、版本号与构建号；未推送、未安装依赖、未访问网络。
- **崩溃结论的写法**：凡是无法用 crash log 证明的，一律写“假设/风险”，不写“已确认根因”。

### 11.2 #1 连续缩窗 / 后台重开 / 点迷你播放器崩溃（最高优先级）

- **问题**：连续拖动窗口改变尺寸时崩溃；App 退后台后不杀进程再打开仍可能崩溃；点击迷你播放器也可能崩溃。没有 crash log。
- **本轮确认的代码风险（不是已证实的根因）**：
  1. 浮动播放器原先挂在每个 Tab 的 `NavigationStack.safeAreaInset` 上。宽/紧凑两套迷你播放器在 618pt 附近切换时，inset 高度会突然变化；缩窗或键盘改变安全区后，旧安全区高度可能残留，表现为布局跳变或反馈循环。这是**假设**。
  2. `TabletMiniPlayerView` 原先用 `ViewThatFits`。`ViewThatFits` 会测量两个候选分支，而两个分支都带同一个 `matchedTransitionSource(id:in:)`；`tabViewBottomAccessory` 的 content 在 iOS 26.1 分支即使 `isEnabled:false` 也会被构建。同一命名空间里出现重复 transition source，是点击/重开时崩溃与 zoom 转场抖动的一个**未证实假设**。
  3. `NowPlayingTabletLayout.playerWidth` / `panelWidth` 在瞬时 0 宽几何（Stage Manager 拖拽、旋转、分屏过渡）下可能得到负值，随后用于 `.frame(width:)`。这是确定的代码缺陷风险（负 frame 至少会触发无效布局），但**没有证据证明它就是本次崩溃**。
  4. `PlaylistTrackList` 在 C25 后使用 `ForEach(tracks.indices, id: \.self)` 并直接 `tracks[index]`；列表刷新或删歌与 SwiftUI diff 交错时存在越界风险。这也是**假设性风险**，不是已复现的崩溃。
- **改动**：
  - `0149d95`：浮动播放器改为内容底部 overlay，显式 `.ignoresSafeArea(.keyboard, edges: .bottom)`；用固定 76pt 透明 `safeAreaInset` 保留滚动 clearance；移除 `ViewThatFits`，由容器宽度只选择一个分支；`tabViewBottomAccessory` 只在真正启用时构建内容。这样同一时刻只有一个 `matchedTransitionSource`。
  - `9d36b04`：把透明 clearance inset 放在 bar overlay 之前，确保 overlay 贴的是外层内容/窗口底边，而不是 spacer 的顶边；避免固定 76pt 又把胶囊顶上去。
  - `b3908f2`（follow-up）：浮动播放器从“每个 Tab 的 NavigationStack overlay”进一步移到 `TabView` 根级 overlay。键盘/Stage Manager 改变的是 Tab 内容安全区，根级 overlay 不再受其 frame 缩短影响；同时宽布局阈值改为 `可用宽度 - 28pt 外 padding - 16pt 内 padding >= 618pt`。这仍是**代码层修正，未真机验证**。
  - `3b3c82c`：`playerWidth` / `panelWidth` 下限钳到 1pt；`PlaylistTrackList` 改为按 `Song.id` 稳定身份 + 索引字典；`MusicCollectionDetailLayout` 的宽度回调按 8pt 量化，降低连续拖窗时的整页重建频率。
- **重测**：仅 `swift-frontend -parse`（通过）和新增静态检查（通过）。**未做真机**：需要在 iPad Stage Manager 中连续拖拽窗口跨越 558/618/710pt、退后台再打开、反复点迷你播放器，并用 Console 检查 AttributeGraph 循环、重复 transition source、负 frame/无效尺寸日志。**不能宣称崩溃已修复**。

### 11.3 #2 拖动进度条需要缓冲数秒；播放开始后缓存整首

- **问题**：拖动 seek 经常要等数秒才出声；希望播放开始后把整首安全地缓存到本地。
- **原因**：播放引擎是 vendor `AudioStreaming`，不是 AVPlayer；`AudioPlaybackDeck` 直接对流式 URL 做 HTTP 范围请求，暂停/seek 后仍要重新等 CDN。此前只有下载库（用户主动下载）提供本地文件，没有“临时整曲缓存”。
- **改动**（`c90f62d`）：
  - 新增 `MeloX/Core/Playback/Cache/PlaybackTrackCache.swift`：在**首次播放真正开始之后**再启动后台整曲下载，不阻塞起播。
  - 存储位置 `Caches/MeloX/PlaybackCache`；总量上限 512MB、单曲 128MB、7 天 LRU；写入前校验 HTTP 200、长度、MIME 与音频头（ID3/FLAC/M4A/WAV/AIFF/CAF/AAC），按实际内容推导扩展名，拒绝 HLS/m3u8、Ogg/APE（AudioStreaming 的文件源不支持）和明显错误 MIME。
  - 下次播放同一首歌且质量匹配时，先解析远端 URL（确认可播放/账号状态），再用本地文件替代流；缓存文件失效时自动删除并回退流式。
  - 拖动 seek 时如果整曲文件已完成、当前仍是流式、且不在 AutoMix 转场中，则异步切换到本地文件并定位到目标位置；切换期间的后继拖动只记录最新位置，加载完成后补一次 seek。失败自动回退流式；再次失败会删除缓存并重载。
  - 换歌、队列结束、最终播放失败会取消缓存任务；缓存随“清除网络/封面缓存”一起清理，并计入存储用量。
  - `b5a3779`（follow-up）：不再用 `URLSession.shared.download` 先落盘再检查上限，而是用 `URLSessionDataDelegate` 逐块写入临时文件。Content-Length 已声明时在收到首包后立即拒绝（`expectedContentLength > 128MB`）；chunked/未知长度时按累计字节在超过 128MB 时 `cancel()`，因此传输过程中就有硬上限。启动前要求磁盘至少保留“128MB 单曲上限 + 128MB headroom”，同一时刻只允许一个整曲传输；任务取消与 delegate 启动之间做了竞态保护。
  - `9121275`（follow-up）：cached seek 交接在 `cachedSource` 返回后先校验 token/generation/song，再决定清理或加载；旧完成的回调不会清掉新交接的 flag/待定位位置。打开本地文件前重新读取 `currentLoadShouldAutoplay`（而不是沿用 seek 时的旧 bool），等待期间用户按下的暂停/播放会在加载后保持一致；重复播放（repeat one）不再依赖单独的 autoplay 参数。
- **明确限制**：
  - **下载完成前的 seek 仍可能缓冲**；不能承诺“永远秒开”，也不能在文件未完成时声称已切到本地。
  - 文件刚完成后的**第一次** seek 需要打开本地 deck，可能有短暂 loading/断点；之后才受益。
  - 当前实现先解析远端 URL 再查本地缓存，因此**离线启动不能直接播缓存文件**。
  - **不是 AVAssetResourceLoader，也不是与播放器共享的 progressive downloader**。内置引擎是 vendor `AudioStreaming`，它不接受 resource loader；在现有约束下，后台整曲文件缓存是“最近的”安全方案，但不能说成共享同一个流式下载。
  - 低磁盘时直接跳过缓存（播放不受影响）；128MB 单曲上限和 128MB headroom 是写死策略，未做成设置项。
  - 不带自定义 Cookie/请求头（与现有流式播放一致）；依赖 CDN 签名 URL。DRM/FairPlay 没有专门检测，只靠 MIME 与音频头拒绝明显不可缓存内容。
  - 质量变化会生成新的缓存键；旧质量文件在下一次同曲下载时删除。
- **重测**：未编译、未运行。真机需验证：起播是否仍立即开始；缓存目录是否只出现一个文件；完成后首次 seek 的停顿；连续拖动；切歌取消；磁盘上限；清除缓存；离线/弱网；不同音质；下载库歌曲不走缓存。

### 11.4 #3 自己的歌单与“我喜欢的音乐”隐藏收藏/订阅按钮

- **问题**：自己的歌单显示对勾但点击无效果；喜欢歌曲歌单点击收藏会报错。
- **原因**：`MusicCollectionPrimaryActions` 无条件渲染收藏圆钮，`PlaylistDetailView` 的更多菜单也无条件渲染。`LibraryStore.toggle(playlist:)` 的 `canUnsubscribe` 只保护“取消收藏”，喜欢歌曲歌单不在 `favoritePlaylists` 里，因此会被当成“订阅”请求；自己的歌单同样会走订阅路径。服务器拒绝后表现为报错或无效。
- **改动**（`683c9dc`）：新增 `LibraryStore.canToggleSaved(_:)`：`likedPlaylistID` 一律返回 false；`profile.userID` 与 `playlist.creator.userID` 相同时返回 false；**身份未知（未登录或 profile 未加载）时保持按钮可见**，不猜测归属。标准歌单页头、排行榜页头与更多菜单都改为按该函数渲染。
- **重测**：静态检查通过。真机需分别验证自己的歌单、喜欢歌曲、他人公开歌单、已订阅歌单、退出登录、profile 尚未加载完成六种状态；重点确认“更多”菜单不残留空 Divider/空项。

### 11.5 #4 喜欢歌曲列表时长贴近右边缘

- **问题**：收藏/喜欢歌曲列表的时长文字比其它列表更靠右，几乎贴边。
- **原因**：该页依赖 `List` 的默认 row inset，而歌单/专辑详情使用显式的 20/26pt 尾部间距。不同容器/尺寸类下默认 inset 不一致，导致视觉不齐；这是按代码与症状推断，**没有截图可量测**。
- **改动**（`eef12fa`）：只在 `LibrarySongsView` 的歌曲行设置 `listRowInsets(top: 8, leading: 20, bottom: 8, trailing: 20)`，用行级 inset **替换**默认 inset，而不是在共享 `TrackRowView` 里再加一层 padding，避免双重间距；其它列表保持原样。
- **重测**：静态检查通过。真机需在 iPhone/iPad、常规/紧凑宽度下对照喜欢歌曲与歌单详情的时长右边缘，并确认行高、swipe action 与点击区域未变化。

### 11.6 #5 分屏缩窗或键盘（搜索）后浮动播放器停在屏幕中间

- **问题**：Stage Manager 分屏缩窗或搜索键盘出现/消失后，迷你播放器胶囊停在屏幕中部，不贴底，并伴随跳动。
- **原因**：浮动播放器挂在每个 Tab 的 `NavigationStack.safeAreaInset` 上；键盘和窗口尺寸变化会改变安全区，inset 可能保留旧高度。宽/紧凑两种播放器高度不同，切换时 inset 高度也会跳变。以上是**代码层假设**，没有布局调试日志。
- **改动**（`0149d95`、`9d36b04`、`b3908f2`）：先改为 `Tab` 内容底部的 `.overlay(alignment: .bottom)`，再在 follow-up 中把 overlay 提升到 `TabView` 根级（`playerAwareTabView`），bar 显式忽略键盘安全区，按 `proxy.safeAreaInsets.bottom + 8` 贴在实际窗口底部安全区上方；滚动内容仍用固定 76pt 的透明 `safeAreaInset` 保留底部 clearance，该 inset 只存在于当前 Tab，不包含播放器，不再随播放器高度/键盘变化。根级 host 不会因键盘出现而被缩短，因此不存在“旧安全区高度写回”的路径。宽/紧凑分支由根级 `GeometryReader` 的实际可用宽度决定：先扣 28pt 外 padding 和 16pt 内 padding，再与 618pt 最小控件宽度比较，避免 618pt 可用宽度里塞入 618+16pt 内容。
- **HIG**：对应 Layout 的“respect system-defined safe areas”和“design based on actual available space, not device type or orientation”；用几何实际宽度而不是设备/方向判断。仍**未真机验证**，不能宣称贴底问题已解决。
- **重测**：静态检查通过。真机需验证：分屏拖动窗口、旋转、键盘弹出/收起、切换 Tab、播放器宽/紧凑切换后胶囊始终贴底；列表最后一行不被遮挡；76pt 是否过多/过少需目测。

### 11.7 #6 流畅度：转场、取色、缩略图、歌词刷新

- **歌单封面取色卡顿**（`ec366dd`）：确认了一个真实缓存 bug——详情页 init 用原始 `coverURLString` 查 `ArtworkAccentColorProvider` 缓存，而加载任务用 `Playlist.artworkURL` / `Album.artworkURL`（会补 https、清空 CDN 的 imageView 参数并追加 `param=1024y1024`）。键永远不一致，所以每次重进都重新下载并提取。现在 init 与导航转场 prefetch 都使用规范化后的 summary URL，命中已有 actor 缓存。**该 actor 与 per-URL `assetsCache` 是本轮之前就存在的实现**；取色本来就不在主线程，本轮只修 key 规范化，没有改算法，也没有“新增 actor”。
- **缩略图重载/spinner**（`8bb2008`、`5fe6e87`）：Nuke 的 request 以 thumbnail 像素尺寸为键，布局轻微变化就会换 key。现在把像素尺寸量化到 16pt 步长；增加按 URL 的 SwiftUI.Image 内存桥接层（128 条/64MB），新 request 未完成时先显示同一封面的上一张图。follow-up 中桥接层改为由 Nuke 成功响应的 `state.response` 写入（不再依赖 `onChange`/onAppear 生命周期），并按 `CGImage.bytesPerRow * height` 的真实解码字节数计费，而不是固定 512KB；桥接层与 Nuke memory cache 共享同一批解码 buffer，不产生第二次 decode。Nuke 自身的 memory cache + DataCache 仍是主路径，桥接层只覆盖“同一 URL、不同量化尺寸”的窄缺口，没有新增 prefetch，也没有复制 Nuke 缓存。
- **启动时 URLCache 预算**（`8bb2008`）：启动时把 `URLCache.shared` 设为 64MB 内存 + 512MB 磁盘，供 Nuke 与取色下载复用。**Nuke 自身是否使用 `URLCache.shared` 取决于其 DataLoader 配置，本轮没有改 Nuke pipeline，需真机/网络面板确认。**
- **迷你播放器到全屏转场**（`0149d95`、`b3908f2`）：同一时刻只构建一个迷你播放器分支、只注册一个 matched transition source，去掉 `ViewThatFits` 对两个分支的测量；follow-up 把该 source 放到根级 overlay。**没有替换 iPad 上的系统 native zoom**：仍是 `.navigationTransition(.zoom(sourceID:in:))` + `matchedTransitionSource`，连续性由系统 zoom 从同一 artwork source 展开保证；本轮只是消除重复 source 的崩溃/抖动风险。没有帧率/耗时测量。
- **歌词 60fps C3 / ProMotion**（`fbc7fb5`）：C3 的 60fps 硬编码只保留在歌词页背后（模糊且大部分被歌词遮挡）；其它页面按 `effectiveLyricsRefreshRate` 使用用户设置（含 Low Power Mode→30、ProMotion 选项）。歌词文字本身的 TimelineView 原本就使用该环境值，本轮未改。Reduce Motion 仍通过 `pausesAnimation` 暂停，未绕过。是否真正省电/更顺需真机与 Instruments。
- **重测**：静态检查通过。真机需对比首次/重复进入歌单的取色时间、图片请求数、缩略图 spinner、转场帧率、歌词页与非歌词页的帧率/发热，并检查 Reduce Motion 与低电量模式。

### 11.8 本轮提交清单

| # | SHA | 类型 | 说明 |
| --- | --- | --- | --- |
| 1 | `c90f62d` | fix(playback) | 整曲后台缓存、seek 本地交接、取消/校验/上限（#2） |
| 2 | `ec366dd` | perf(artwork) | 用规范化封面 URL 命中详情调色板缓存（#6） |
| 3 | `683c9dc` | fix(collection) | 自己/喜欢歌曲歌单隐藏收藏按钮（#3） |
| 4 | `3b3c82c` | fix(layout) | 负尺寸钳制、稳定行身份、宽度回调量化（#1） |
| 5 | `eef12fa` | fix(library) | 喜欢歌曲行显式尾部 inset（#4） |
| 6 | `0149d95` | fix(mini-player) | 浮动条贴底、忽略键盘、单一 transition source（#5 与 #1 的共同风险） |
| 7 | `8bb2008` | perf(artwork) | 缩略图尺寸量化、URL 内存缓存、URLCache 预算（#6） |
| 8 | `fbc7fb5` | perf(lyrics) | 非歌词页恢复自适应刷新率（#6） |
| 9 | `e01fa9c` | test | 13 项静态回归检查 |
| 10 | `9d36b04` | fix(mini-player) | clearance inset 置于 overlay 之前（#5） |
| 11 | `b5a3779` | fix(playback) | 传输中字节上限、磁盘 headroom、单传输（#2，follow-up） |
| 12 | `9121275` | fix(playback) | 交接 token 校验与当前暂停意图（#2，follow-up） |
| 13 | `5fe6e87` | perf(artwork) | 缩略图桥接按真实解码成本计费（#6，follow-up） |
| 14 | `b3908f2` | fix(mini-player) | 根级 overlay 与含内 padding 的宽度预算（#5，follow-up） |
| 15 | `1db132d` | test | follow-up 静态检查（共 17 项） |

- 首轮另有 1 个文档提交，follow-up 另有 1 个文档提交记录本节；未改版本号、构建号、签名、workflows、pbxproj；未推送。
- `.fix/` 与 `.permission-probe-agent` 保持未跟踪原状，未写入。follow-up 未改 `.agent-notes.md`。

### 11.9 静态验证结果（全部可复现）

- **语法解析**：首轮对 `59cb8ec..HEAD` 全部 17 个改动/新增 Swift 文件运行
  `~/opt/swift-6.3-RELEASE-debian12/usr/bin/swift-frontend -parse <file>`，全部 `rc=0`；follow-up 又对 `PlaybackTrackCache.swift`、`PlayerStore.swift`、`ArtworkImage.swift`、`ContentView.swift` 运行，全部 `rc=0`。**这只证明语法可解析，不证明类型检查、链接或运行通过。**
- **新增静态回归**：`cd Tools/Tests && python3 test_device_round2.py -v` → **17 项全部 OK**（首轮 13 项 + follow-up 4 项）。覆盖：缓存上限/磁盘 headroom/流式传输中截断/单传输、取消与存储位置、PlayerStore 接线与交接 token/意图顺序、稳定行身份、负尺寸钳制、宽度量化、收藏动作可见性、尾部 inset、根级浮动条 overlay/keyboard、含内 padding 的宽度预算、单一迷你播放器分支、调色板 URL、缩略图真实解码成本、自适应背景刷新。
- **空白检查**：`git diff --check 59cb8ec..HEAD` → 通过。
- **未运行**：没有 `xcodebuild`、没有 App/模拟器、没有 Instruments、没有网络抓包、没有真机 UI/Stage Manager/键盘/无障碍验证。
- **旧的 `Tools/Tests/*.py`**：依赖 macOS/Swift 与 GRDB 等环境，本轮未运行；不能把它们的旧结果当作本轮证据。

### 11.10 仍需编译 / 真机验证的事项

1. **编译**：新增的 `BoundedTrackTransfer`（`URLSessionDataDelegate`、`@unchecked Sendable`、continuation/URLSession 生命周期）、`PlaybackTrackCache` 的磁盘 headroom API、`ArtworkImage` 的 `state.response`/`CGImage` 成本计算、`ContentView` 的 `Group` + 根级 overlay/`GeometryReader`、`PlayerStore` 去掉 `autoplayAfterCachedHandoff` 后的调用点，均**未做 Swift 类型检查**。尤其需要确认所使用的 Nuke 13 `LazyImageState.response` / `ImageResponse.image` 与 Swift 6 严格并发下的 delegate 写法。
2. **崩溃复现**：按 11.2 的拖窗/重开/点击路径重复测试；重点看 Console 是否有 AttributeGraph 循环、重复 matched transition source、负 frame/无效尺寸。
3. **缓存**：真实 CDN 的 200/MIME/头校验、带签名的重定向、不同音质、下载库共存、切歌取消、缓存清理、离线、磁盘上限。
4. **UI**：11.4 的六种账号状态、11.5 的尾部对齐、11.6 的贴底与 76pt clearance、11.7 的 spinner/转场/刷新率。
5. **无障碍/减弱动态**：Reduce Motion 下背景与转场仍应暂停/降级；VoiceOver 下隐藏的收藏按钮不应留下空标签。
6. **性能**：取色 actor 的实际耗时、URLCache 命中、缩略图请求数、歌词页/非歌词页帧率与发热，均需 Instruments/网络面板。

### 11.11 本轮明确未做

- 未编译、未运行 App、未真机验证、未看截图、未取得 crash log。
- 未改 `MeloXDesktop`、Watch、Widget 的同名实现；本轮只修 iOS target。
- 未新增本地化 key，未改 `project.pbxproj`（新 Swift 文件由文件系统同步组自动加入 MeloX target；这一点也未在 Xcode 中验证）。
- 未把全曲缓存做成用户可配置项；512MB/128MB/7 天/128MB headroom 是写死策略，后续可按存储设置调整。
- 未改 `DownloadStore.init` 的同步 GRDB/文件检查，也未改 `PageContentCache.store` 的 MainActor JSON 编码；owner analytics 只作为后续 focused follow-up 的依据。
- 未改 `.agent-notes.md`（follow-up 指令要求不动；此前误加入的 session ID 由协调者从未发布文档提交中移除）。

### 11.12 Apple HIG 对照（Motion / Layout，逐项 UI 映射）

依据官方 HIG 页面（本地快照 `.out/round2/hig-motion.txt`、`hig-layout.txt`；Motion 快照标注 2025-09-09 更新，Layout 快照标注 2026-09-09 更新）。原则：动作要有目的且短暂精确、可被用户取消、尊重 Reduce Motion；布局按实际可用空间/尺寸类适配、对齐并用一致边距、尊重安全区、尺寸变化时保持功能一致。

| 本轮 UI 改动 | 对应 HIG 指引 | 实现与边界 |
| --- | --- | --- |
| #1 连续缩窗：负尺寸钳制、稳定行身份、宽度回调量化 | Layout: “Design a layout that adapts gracefully and consistently”; “Keep functionality the same as size classes change” | 只把几何钳到安全值、稳定 `Song.id` 身份、按 8pt 量化重建，不改功能；未真机验证 |
| #4 喜欢歌曲行尾部 20pt inset | Layout: “Align elements…”; “Use consistent spacing” | 与歌单/专辑详情统一 trailing，替换默认 inset 而非叠加，避免双重间距 |
| #5 浮动播放器贴底/键盘/分屏 | Layout: “respect system-defined safe areas”; “design based on actual available space, not device type or orientation” | 根级 overlay + `.ignoresSafeArea(.keyboard)` + `safeAreaInsets.bottom`；宽布局按几何宽度扣 28pt 外 padding + 16pt 内 padding，而不是按设备/方向判断 |
| #5/#6 迷你播放器 → 全屏转场 | Motion: “Add motion purposefully”; “Aim for brevity and precision in feedback animations”; “Let people cancel motion”; “Make motion optional” | **保留 iPad 系统 native zoom**（`.navigationTransition(.zoom)` + 单一 `matchedTransitionSource`），不从 mini 视图自建替代动画；连续性来自同一 artwork source；未新增全局动画，Reduce Motion 仍由系统与现有 `pausesAnimation` 生效 |
| #6 缩略图淡入、背景刷新 | Motion: 避免无意义/过度动画；系统组件已提供反馈 | 缩略图 0.18s easeOut 仅在 Reduce Motion 关闭时；歌词页背后保留 60fps，其它页面按环境刷新率降频；没有为“看起来更精致”增加装饰性动画 |
| 整体内容优先/克制 | Layout: “Order content by relative importance”; “Differentiate controls from content” | 未新增无意义控件；浮动条只保留播放/上一首/下一首/打开播放器；透明 clearance inset 不参与视觉层级 |

### 11.13 现有实现 vs 本轮新增（诚实归属）

- **取色**：`ArtworkAccentColorProvider` 及其 per-URL `assetsCache` 是**既有** actor 实现；本轮只修复查询 key 的 URL 规范化（`ec366dd`），没有把取色首次移出主线程，也没有新增取色缓存。
- **Nuke 缓存**：Nuke 的 memory cache + DataCache 与 `URLCache.shared` 预算（`8bb2008`）是缩略图的主路径；`ArtworkImageMemoryCache` 是首轮新增的窄用途桥接层，follow-up（`5fe6e87`）只改写入时机与成本计算，并让它共享 Nuke 的解码 buffer，没有另建一套图片下载/解码缓存。
- **Prefetch**：没有新增 prefetch；侧栏 40 张与导航转场 prefetch 保持首轮的有界实现。
- **整曲缓存**：`PlaybackTrackCache` 是首轮 `c90f62d` 新增；follow-up（`b5a3779`）只加固传输上限/磁盘 headroom/单传输，没有新增第二个缓存或把播放器改成共享 progressive downloader。
- **主线程 I/O**：`DownloadStore.init` 的同步 GRDB/文件检查与 `PageContentCache.store` 的 MainActor JSON 编码是**既有**实现，本轮未改；owner analytics 只用于提出后续 focused follow-up，不作为本轮已修复项。
