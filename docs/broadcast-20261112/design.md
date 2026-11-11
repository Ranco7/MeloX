# 系统音频识曲 / System audio recognition

## 简体中文

### 重签兼容

b1b4e3b 后的设备测试出现启动前通用不可用；已确认旧源码把实际扩展 ID 与缓存 Info ID、固定扩展文件名及新组名绑定。具体设备失败项尚无诊断，不能断言，也不归因于证书组能力不足。

当前改为按识曲协议标记、extension point／mode／principal marker 发现实际扩展，将真实 Bundle ID 交给公开 picker。主 App 和扩展共用有界公开 profile XML 解析器，优先取双方组交集，再用配置与已有组回退；所有候选都必须通过各进程的系统容器访问和唯一小文件读写探测。声明不是授权，不做 CMS 密码学认证，不记录完整 profile、证书或设备数据。

最多 8 个候选容器投递同一 UUID，扩展仅确认一个共同可访问组。请求／状态／控制绑定 UUID、实际扩展 ID 和组名，未确认或错配时不使用音频。每个容器最多两个会话目录；独立采集期限和挂起返回机制不变。正常说明仍无受保护音频警告。错误页提供可展开安全诊断，12 秒未确认先给帮助，60 秒到期明确区分“未收到确认”，不擅自推断扩展权限原因。

源 entitlements 和配置已改为复用既有 `group.azki.moye.MeloX`，仅使用识曲自己的子目录；legacy 保留该组名，App／扩展 Bundle ID 仍按身份改写。以下旧流程的采样／隐私约束仍有效，组配置表已同步更新；运行时算法见 `MeloXBroadcastShared/BroadcastRuntime.swift` 和 `BroadcastMailboxSet.swift`，回归入口见下文；源码与构建检查不能替代设备重签实测。


### 行为与实现

“设备音频”使用 ReplayKit Broadcast Upload Extension 采集其他 App **允许系统共享**的音频，适合切换到音乐 App 播放后返回识别。原生广播按钮可见、直接由用户点击，指定已嵌入扩展的完整 Bundle ID，并隐藏麦克风选项。系统仍将画面缓冲交给扩展，本功能立即忽略视频及麦克风，只临时保留音频；不保存或发送任何画面。

主 App 在自己的 actor 中检查扩展和 App Group 的读写可用性，然后准备 UUID 会话，最多等待 60 秒开始，并在约 12 秒仍未确认时提供启动帮助。扩展再独立检查共享容器、未过期且未使用的会话及取消指令；缺失权限不会强制解包或影响播放器与麦克风。App 无法在广播开始前证明扩展实际签名获得了共享权限，扩展启动时会再次核验；失败时系统显示结束阶段，App 提供未确认帮助，并最迟在启动等待到期时显示可展开诊断。

扩展同步处理有界音频回调，不排队保留 `CMSampleBuffer`。按 ASBD 判断 PCM 类型、字节序、步幅和声道布局，支持常见 44.1/48 kHz planar/interleaved Float32/64 和 signed Int16/24/32。大端 Int16 不当作 Float32；PTS 只用于检查连续性。先算术平均声道，再用 63 tap FIR 低通和带状态插值转换成原指纹链路所需的 8 kHz mono。暂停／恢复、格式或时间戳断点会丢弃旧窗口，避免拼接不同片段。

单次保留最多 9 秒（72,000 帧／288,000 字节）的连续 PCM。配置 3/6/9 秒时按该长度采集，“连续识别”在此模式下明确改为单次 9 秒，麦克风连续识别保持原样。开始时先等有效声音；12 秒无缓冲或持续静音会友好结束。扩展以自身单调时钟执行总期限 `duration + 15` 秒，因此即使 App 挂起、终止、广播暂停或没有回调，也会主动结束。用户在系统面板停止时，已有足够声音则保留供返回识别，不足则提示无可用音频。

每个已通过探测的共享容器中，`RecognitionBroadcast` 包含一个当前 request 和最多两个 UUID 子目录（候选最多 8 个）。每个会话有一个控制文件和一个二进制 plist 原子快照；PCM、状态、心跳位于同一个 envelope，单文件上限 320 KB。快照最多约每秒写一次，控制读取由独立一秒定时器触发。只有扩展进程内的短锁，没有跨进程文件锁，也不依赖 Darwin 通知唤醒 App、socket 或后台保活。请求、控制和快照均绑定 UUID／实际扩展 ID／所选组；旧控制／旧快照不会覆盖新 UUID。新会话会清理更旧目录；匹配处理完成后清除 PCM。未返回或失败时仍可能保留最多两个本地快照，下一次准备时有界清理；不宣称定时安全擦除。

App 挂起时由扩展继续采集并自行停止。返回前台后 App 才读最终快照、调用现有 WebKit 指纹运行时及网易匹配；本机 PCM 读取、转换和序列化在后台执行，指纹计算由 WebKit 内容进程执行，仅 UI／WebKit API 留在主 actor。重新进入识曲页时可恢复 10 分钟内尚未处理的非取消会话（含待显示的静音／错误）；不自动重开广播。过期请求、取消请求和已使用请求不会再启动采集。系统时钟改动、系统杀死扩展或原服务不可用仍可能导致可恢复错误。

### 文案与验证状态

来源为“麦克风／设备音频”（存储标识保持原样）。麦克风限定说明保留 `%@`，跟随 3/6/9 秒偏好，默认 6 秒；连续说明持续到用户停止。设备音频说明用户手动开启屏幕广播、只处理音频、红色系统指示、采集自动结束及返回 MeloX 后识别。画面不保存／不发送，正文按自然高度换行。设置页按音源展示真实采集上限；麦克风不显示设备音频的共享权限要求。

静态选项／正常等待页不展示受保护音频警告；仅实际静音／无音频失败允许说明该原因。技术限制仍保留在本文，实际中英 UI 文案见 `MeloXLocalization/{zh-Hans,en}.lproj/Localizable.strings`。

定向回归：`PYTHONPATH=Tools/Tests python3 -m unittest test_broadcast_capture test_listening_polish test_song_row_alignment -v`；独立 PCM／状态检查：`bash Tools/Tests/run_broadcast_mac_checks.sh`。这些检查覆盖真实 CMSampleBuffer、大端 PCM、有界窗口及状态机，但不能代替真机权限、视觉和性能验证。

### 打包与安装限制

| 构建身份 | App | Broadcast Upload Extension | 两者必需的识曲 App Group |
| --- | --- | --- | --- |
| TestFlight | `azki.moye.MeloX` | `azki.moye.MeloX.BroadcastUpload` | `group.azki.moye.MeloX` |
| legacy | `moye.MeloX` | `moye.MeloX.BroadcastUpload` | `group.azki.moye.MeloX` |

App 原有共享组及 widget／Live Activity 存储代码保留不变。识曲复用已有 `group.azki.moye.MeloX` 的独立子目录，legacy 临时工程仅改 Bundle 身份并保留此组名。App 与扩展的源 entitlements 均声明该组，运行时也能尝试公开元数据中的有效改写组；扩展有依赖和嵌入阶段，无额外第三方依赖。构建脚本继续完全禁用签名，并附上 `BroadcastSigningRequirements.plist` 供重签检查；该元数据和未签名 IPA **不会授予权限**。两个目标仍需实际获准访问同一共享组，并保留扩展；即使证书支持 App Groups，实际签后组名和双方访问仍需设备验证。

Apple Music 订阅等 DRM／受保护音频可能静音或不可用，系统、播放 App 和设备条件也影响结果。没有保证所有音源可采集，也没有绕过保护。未签名构建、源码测试不能验证实际跨 App 权限或设备上的音源覆盖率。

### 依据与边界

1. [Apple：RPSystemBroadcastPickerView](https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview.md)：使用可见的公开 picker、`preferredExtension` 和 `showsMicrophoneButton`；不遍历内部按钮或伪造点击。
2. [Apple：RPBroadcastSampleHandler](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler.md) 与 [结束广播 API](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler/finishbroadcastwitherror(_:).md)：回调串行，sample buffer 模式。停止 API 需要 Error，因此正常完成也提供中性的本地化结束原因，系统可能仍显示其错误式提示。
3. [Apple Platform Security：ReplayKit](https://support.apple.com/guide/security-pdf/replaykit-security-seca5fc039dd/web)：进程隔离和原始缓冲；只处理音频是本扩展的策略，系统广播授权本身仍涉及屏幕。
4. [HaishinKit #1384](https://github.com/shogo4405/HaishinKit.swift/issues/1384)：实际扩展排队转换导致内存崩溃的报告；这是工程警示，不能据此把约 50 MB 当成所有设备的承诺额度。
5. [PCM 大端格式讨论](https://stackoverflow.com/questions/64716540/audio-frame-sample-type-in-pcm)：`0xe` 为 signed packed big-endian Int16 的实际案例；解码依据 ASBD，不将该案例当作所有 ReplayKit 版本的固定格式。
6. [App Extension IPC](https://7strikes.dev/articles/app-extension-ipc/)：持久共享邮箱、挂起及通知的限制；本实现选择低频轮询，不假设 Darwin 通知能唤醒挂起进程，不使用 iOS 不可用的 CFMessagePort。
7. [Zoom iOS share troubleshooting](https://godevelopers.zoom.us/docs/video-sdk/ios/share/troubleshooting/)：扩展嵌入及双方 App Group 配置核查；不是某个重签工具的兼容认证。
8. [重签丢失 App Groups 的实际案例](https://hparis.github.io/blog/2023/02/06/如何避免-App-被重签名/)：缺少容器时应降级处理，不强制解包；不由此推断任意证书都能获得该权限。

## English

### Re-signing compatibility

A device test after b1b4e3b failed before launch with a generic unavailable message. The confirmed source guard coupled the actual extension ID to a cached Info value, a fixed extension filename and a newly named group. The exact failed device check remains unknown; certificate group capability is not blamed.

Runtime discovery now uses a recognition protocol marker, extension point/mode and principal marker, passing the actual bundle ID to the visible public picker. Both processes share bounded public-profile XML extraction, preferring the profile intersection before configured/established fallbacks. Every candidate must pass that process’s actual system-container and unique tiny read/write probe. Declarations are not grants; no CMS authenticity verification or full profile/certificate/device logging occurs.

Up to eight candidate containers carry one UUID; the extension acknowledges only one usable common group. Requests, control and snapshots bind UUID, actual extension ID and group; unconfirmed or mismatched audio is rejected. Each container has at most two session directories. Independent capture deadlines and foreground-return matching remain. Normal descriptions contain no protected-audio warning. Collapsible safe diagnostics provide unconfirmed-start help at about 12 seconds and an explicit final stage at expiry, without inferring an extension permission failure.

Source entitlements/configuration now reuse established `group.azki.moye.MeloX` in a recognition-only subdirectory. Legacy preserves the group while still rewriting app/extension bundle IDs. The sampling/privacy constraints below remain; the group table is updated. The runtime algorithm is in `MeloXBroadcastShared/BroadcastRuntime.swift` and `BroadcastMailboxSet.swift`, with regression entry points below. Source and packaging checks do not replace re-signed-device testing.


### Behavior and implementation

Device Audio uses a ReplayKit Broadcast Upload Extension for audio that other apps **allow the system to share**. Start the visible native broadcast picker, switch to the music app, then return to recognize the song. The picker specifies the exact embedded extension ID and hides the microphone option. The system still delivers screen buffers; the extension ignores video and microphone buffers immediately. No screen data is saved or sent.

The host checks the embedded extension and App Group read/write access on its own actor, prepares a UUID request, and allows 60 seconds to start. The extension independently checks its container, unexpired unused request and cancellation control. Missing permissions fail safely. The host cannot prove the extension's actual signing permissions before launch; the extension rechecks them and reports a friendly system completion reason. The host's waiting state is bounded even if the extension cannot reach the mailbox.

Audio callbacks are processed synchronously with bounded copies, without queuing CMSampleBuffers. ASBD determines PCM encoding, byte order, stride and channel layout, including typical 44.1/48 kHz planar/interleaved Float32/64 and signed Int16/24/32. Big-endian Int16 is decoded correctly; PTS is only a continuity check. Arithmetic channel averaging, a 63 tap low-pass FIR and stateful interpolation produce the existing fingerprint pipeline's 8 kHz mono input. Pauses, format changes and timestamp gaps discard the previous window.

Each session retains at most 9 seconds, 72,000 frames or 288,000 PCM bytes. Settings of 3/6/9 seconds are respected; continuous recognition means one explicit 9-second capture in this mode. Microphone continuous recognition is unchanged. Capture waits for sound before spending its short window. No buffers or persistent silence finish within 12 seconds; an independent monotonic deadline of `duration + 15` seconds also bounds paused sessions and suspended or terminated hosts. A system user stop preserves enough usable audio for recognition on return, or reports missing audio.

Each probed shared container holds a `RecognitionBroadcast` mailbox with one current request and at most two UUID directories (up to eight candidate containers), each with one control file and one atomic binary plist envelope containing PCM, status and heartbeat. Files are limited to 320 KB. Snapshots are written at about 1 Hz; a separate 1 Hz timer reads controls. A short in-process lock protects the extension timer, without cross-process locks, Darwin wake assumptions, sockets or artificial background keepalive. UUID, actual extension ID and group bindings isolate stale writers and controls. New sessions clean older directories; completed matching clears PCM. At most two local snapshots can remain after failures or no return, until subsequent bounded cleanup. No timed secure-erasure guarantee is made.

The extension captures and stops while the host is suspended. The host reads the final snapshot and runs the existing WebKit fingerprint and NetEase matching pipeline after foreground return. PCM reads, conversion and serialization run off the main actor; WebKit computes fingerprints in its content process. Entering recognition again can recover an unhandled non-cancelled session, including pending silence/error states, for up to 10 minutes, without restarting a broadcast. Expired, cancelled and consumed requests cannot start again. Clock changes, system termination of the extension and service failures can still produce recoverable errors.

### Copy and validation status

Sources are Microphone / Device Audio, preserving stored identifiers. Limited microphone copy keeps `%@` for the selected 3/6/9 seconds, defaulting to 6; continuous copy states that recognition lasts until the user stops. Device Audio describes a user-started screen broadcast, audio-only processing, the red system indicator, automatic capture completion and recognition after returning to MeloX. No screen data is saved or sent, and body text wraps at its natural height. Settings show the actual capture limit for each source; microphone mode does not show device-audio sharing requirements.

Static options and normal waiting states contain no protected-audio warning. Only actual silence/no-audio failures may explain that cause. Technical caveats remain in this document; exact Chinese and English UI copy is in `MeloXLocalization/{zh-Hans,en}.lproj/Localizable.strings`.

Focused regression: `PYTHONPATH=Tools/Tests python3 -m unittest test_broadcast_capture test_listening_polish test_song_row_alignment -v`; standalone PCM/state checks: `bash Tools/Tests/run_broadcast_mac_checks.sh`. These cover real CMSampleBuffer, big-endian PCM, bounded windows and recognition states, but do not replace device permission, visual or performance verification.

### Packaging and installation limits

| Build identity | App | Broadcast Upload Extension | Required recognition App Group for both |
| --- | --- | --- | --- |
| TestFlight | `azki.moye.MeloX` | `azki.moye.MeloX.BroadcastUpload` | `group.azki.moye.MeloX` |
| legacy | `moye.MeloX` | `moye.MeloX.BroadcastUpload` | `group.azki.moye.MeloX` |

Existing unrelated groups and widget/live activity storage code are unchanged. Recognition reuses established `group.azki.moye.MeloX` in its own subdirectory; the temporary legacy project preserves that group while rewriting bundle identities. Both source entitlements declare it, and runtime also probes valid remapped groups from public metadata. The extension is a dependency embedded in the app, with no third-party packages. The unsigned script keeps signing disabled and adds advisory `BroadcastSigningRequirements.plist` metadata. Neither unsigned metadata nor the IPA grants permissions. Both installed targets must actually access the same group and keep the embedded extension. Even when the certificate supports App Groups, effective remapped names and access still require device verification.

DRM/protected audio, including Apple Music subscription tracks, may be silent or unavailable. System, source-app and device conditions affect capture. There is no promise of universal coverage or protection bypass. Unsigned packaging and source checks cannot establish real cross-app entitlement access or source coverage.

### Sources and caveats

1. [Apple: RPSystemBroadcastPickerView](https://developer.apple.com/documentation/replaykit/rpsystembroadcastpickerview.md): visible public picker, exact preferred extension and hidden microphone option; no internal-button invocation.
2. [Apple: RPBroadcastSampleHandler](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler.md) and [finish API](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler/finishbroadcastwitherror(_:).md): serialized callbacks and sample-buffer mode. The finish API requires an Error; normal completion uses neutral localized text, though the system may present error-style UI.
3. [Apple Platform Security: ReplayKit](https://support.apple.com/guide/security-pdf/replaykit-security-seca5fc039dd/web): process separation and raw buffers. Ignoring video is this extension's policy; system broadcast authorization still concerns the screen.
4. [HaishinKit #1384](https://github.com/shogo4405/HaishinKit.swift/issues/1384): a real queued-conversion memory crash report, not a universal promise of a 50 MB budget.
5. [Big-endian PCM discussion](https://stackoverflow.com/questions/64716540/audio-frame-sample-type-in-pcm): an actual ASBD `0xe` signed packed BE Int16 case, not a fixed format for every ReplayKit version.
6. [App extension IPC](https://7strikes.dev/articles/app-extension-ipc/): durable mailbox and suspension/notification constraints. This implementation polls and does not assume Darwin notifications wake a suspended host or use CFMessagePort on iOS.
7. [Zoom iOS share troubleshooting](https://godevelopers.zoom.us/docs/video-sdk/ios/share/troubleshooting/): embedding and matching group configuration checks, not certification of a re-signing product.
8. [A missing-group re-signing incident](https://hparis.github.io/blog/2023/02/06/如何避免-App-被重签名/): unavailable containers must fail gracefully; arbitrary certificates are not assumed to grant access.

### 重签研究 / Re-signing references

- [Feather entitlement discussion](https://github.com/CLARATION/Feather/pull/611)
- [ESign Bundle ID changes](https://helpcenter.apptesters.org/en/articles/10693796-how-to-duplicate-any-application-when-installing-via-esign)
- [fastlane group rewrite regression](https://github.com/fastlane/fastlane/pull/22058)
- [Ksign release notes](https://github.com/Nyasami/Ksign/releases/)

这些资料说明 ID／组处理可能因工具或版本变化，不能推导所有签名器的固定映射规则。若两份 profile 被移除且组名被改成 Info 与既有回退均未知的名称，将明确报告候选容器不可用，不猜测权限。
These sources show tool/version-dependent ID and group handling, not a universal mapping rule. If both profiles are removed and groups are renamed to unknown values absent from Info and established fallbacks, discovery reports unavailable candidate containers instead of guessing permissions.
