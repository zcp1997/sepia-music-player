# Sepia 开发计划

极简本地音乐播放器：播放你自己 iCloud Drive 文件夹里的音乐和歌词。

## 0. 已确定的约束

| 项 | 决定 |
|---|---|
| 系统 | 最低 iOS 16.0（测试机 iOS 16.6.1），仅 iPhone，竖屏 |
| Bundle ID | `com.zcp.sepia`，固定不变（重签时保持一致才能覆盖安装、不丢数据） |
| 安装 | CI 产出临时签名（ad-hoc，带 `application-identifier`）的 IPA，用户用 TrollStore 安装 |
| 构建 | 本机不装 Xcode，GitHub Actions 是唯一构建途径；仓库公开 |
| 网络 | App 进程零网络请求、无任何网络代码；iCloud 下载由系统完成 |
| 字幕 | 支持 SRT 与 LRC；同名同时存在时 **SRT 优先** |
| 歌词交互 | 网易云式（拖动出现中线 + 时间 + ▶） |
| 数据 | 喜欢、歌单存到**音乐文件夹**里，沙盒留镜像 |
| 依赖 | 零第三方依赖 |

明确不做：随机/单曲循环、搜索、均衡器、封面与 ID3 信息、歌词编辑、任何联网功能。

## 1. 技术栈

- SwiftUI（iOS 16：`ObservableObject` / `@Published` / `NavigationStack`；**不可用** SwiftData、`@Observable`、`scrollPosition(id:)` 等 iOS 17+ API）
- AVPlayer 单实例 + 自管队列；AVAudioSession；MediaPlayer（锁屏/控制中心/耳机）
- 文件夹选择器 + 书签（iOS 用默认 options，`.withSecurityScope` 是 macOS 专用）。选择器用 UIKit 的 `UIDocumentPickerViewController`（Apple「访问目录」文档推荐）。点「打开」无反应的真正原因见第 5 节「为什么要临时签名」：改用 UIKit 后仍复现，所以不是 SwiftUI `fileImporter` 的问题
- 歌词列表：`UITableView` + `UIViewRepresentable`（iOS 16 的 SwiftUI ScrollView 拿不到“开始拖/松手”事件）
- Codable + JSON 持久化
- XcodeGen（`project.yml` 生成工程，`.xcodeproj` 不入库）
- Swift 5 语言模式（避开 Swift 6 严格并发对 AVFoundation 回调的大量报错）

## 2. 项目结构

```
sepia-music-player/
├── project.yml                 # XcodeGen 配置
├── Sepia/
│   ├── SepiaApp.swift
│   ├── Info.plist              # 由 XcodeGen 按 project.yml 生成（不入库）
│   ├── Core/                   # 纯 Foundation 逻辑，本机可用 swiftc 编译测试
│   │   ├── Models.swift        # Song
│   │   ├── LibraryScanner.swift# 递归扫描、iCloud 占位文件、字幕匹配
│   │   ├── CloudFile.swift     # iCloud 下载状态、触发下载、等待下载完成
│   │   ├── LyricsParser.swift  # LyricLine；SRT + LRC 解析、编码识别、当前行定位
│   │   ├── LibraryFile.swift   # Playlist / LibraryData；sepia-library.json 编解码与编辑操作
│   │   └── HeadCacheMath.swift # HeadCacheEntry；ID3 长度、请求区间拆分、缓存文件名哈希
│   ├── Library.swift           # 文件夹授权、书签、扫描；喜欢 / 歌单的读写与合并
│   ├── Player.swift            # AVPlayer、队列、预取、三种起播路径、锁屏控制
│   ├── LyricsLoader.swift      # 当前歌词：等 iCloud 下载、后台解析
│   ├── HeadCache.swift         # 头部缓存、预热；HeadCacheSource（AVAssetResourceLoaderDelegate）
│   ├── FolderPicker.swift      # UIDocumentPickerViewController 选文件夹
│   ├── Log.swift               # os.Logger + Documents/sepia.log
│   ├── AppPaths.swift          # Application Support 目录
│   ├── Assets.xcassets/        # App 图标（单张 1024，由 scripts/make-icon.swift 生成）
│   └── Views/
│       ├── ContentView.swift   # 根视图：未选文件夹时显示引导
│       ├── LibraryView.swift   # [全部|喜欢|歌单] + SongList + 迷你播放条
│       ├── PlaylistViews.swift # 歌单列表、歌单详情、加入歌单
│       ├── PlayerView.swift    # 播放页：歌词、♥、加入歌单、进度条、控制
│       ├── LyricsView.swift    # 网易云式歌词（UITableView 封装）
│       └── SettingsView.swift  # 文件夹、起播缓存 / 预热、版本
├── Tests/CoreTests/            # Core 测试（main.swift 驱动，不依赖 XCTest）
├── scripts/
│   ├── test-core.sh            # swiftc 编译并运行 Core 测试（本机与 CI 共用）
│   ├── typecheck.sh            # 借 Mac Catalyst 对整个 App 做 iOS 16 检查（仅本机）
│   └── make-icon.swift         # 生成 App 图标
└── .github/workflows/build.yml
```

## 3. 功能规格

### 3.1 音乐库
- 选择文件夹 → 书签存 UserDefaults；启动时恢复，`startAccessingSecurityScopedResource()` 在 App 生命周期内一直持有。
- **不需要 iCloud entitlement**：经文件选择器访问 iCloud Drive 无需 iCloud capability（免费 Apple ID 自签也拿不到它）。
- 扫描：递归；扩展名白名单 mp3 / m4a / flac / wav / aac（不区分大小写）；识别 `.歌名.mp3.icloud` 占位文件并还原文件名。
- 歌曲列表不持久化，每次启动/回前台/下拉刷新重新扫描。
- 歌曲 ID = 相对根文件夹的路径（天然唯一，解决重名）。
- 字幕匹配：同目录同名，`.srt` > `.lrc`。
- 列表：全部 / 喜欢 / 歌单；显示文件名（去扩展名）；既不在本地也无头部缓存的歌显示 ☁ 图标。

### 3.2 播放
- 队列 = 点击时所在的列表；列表循环。
- 播放/暂停、上一首、下一首。
- 进度条：拖动期间不让 time observer 回写，松手再 seek。
- 后台：`UIBackgroundModes: audio`；session `.playback`；`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`（含锁屏拖进度）；来电打断后恢复；拔耳机暂停。
- 启动恢复上次歌曲与位置（暂停态）。播放进度只存沙盒 UserDefaults，不写 iCloud。
- 本地文件开启 `AVURLAssetPreferPreciseDurationAndTimingKey`，保证 VBR MP3 拖动后歌词对齐。

### 3.3 歌词
解析（`Core/LyricsParser.swift`）：
- 编码依次尝试：UTF-8 → UTF-16（BOM）→ GB18030。
- LRC：一行多时间戳 `[00:12.34][01:40.00]`；2/3 位毫秒；`[offset:±ms]`；跳过 `[ar:]` `[ti:]` 等标签行；同时间戳两行 = 原文 + 翻译；按时间排序。
- SRT：序号 / 时间轴 / 文本块；`,` 或 `.` 毫秒；多行文本 = 原文 + 翻译；去掉 `<i>` 等标签；只用开始时间。

交互（网易云式）：
- 当前句居中高亮。
- 拖动 → 停止跟随，屏幕中线出现 `01:23 ──── ▶`，中线对准的句子浅高亮。
- 点 ▶ → 跳到该句并播放，恢复跟随。
- 松手 3 秒无操作 → 中线消失，滚回当前句。
- 无歌词显示“暂无歌词”。

### 3.4 喜欢与歌单
- 爱心：播放页按钮 + 列表长按菜单。
- 歌单：新建 / 重命名 / 删除；长按歌曲“加入歌单”；移除；拖动排序。
- 存储：
  - 主存 `音乐文件夹/sepia-library.json`，用 `NSFileCoordinator` 协调写入。
  - 沙盒镜像一份；离线或主文件未下载时读镜像；两边带 `updatedAt`，取新的。
  - 歌曲按相对路径引用；文件改名/移动后该歌在喜欢/歌单中失联（接受）。

```json
{
  "version": 1,
  "updatedAt": "2026-10-27T10:00:00Z",
  "favorites": ["华语/晴天.mp3"],
  "playlists": [
    { "id": "UUID", "name": "通勤", "songs": ["华语/晴天.mp3"] }
  ]
}
```

### 3.5 界面（3 页）
- 主页：顶部分段 [全部 | 喜欢 | 歌单] + 底部迷你播放条。
- 播放页：歌名 / 歌词 / 进度条 / ⏮ ⏯ ⏭ / ♥ / 加入歌单。
- 设置：更换文件夹、重新扫描、预热缓存（带进度）、缓存占用与清空、版本号（含 commit）。

## 4. 起播优化（iCloud 预缓存）

事实：iCloud Drive **没有“只下载前一部分”的公开 API**。文件要么完整在本地，要么是占位符；读取时系统整文件下载完才放行。其他 App “等几秒”就是在等整文件下载。因此“开头”只能由 App 自己留一份。

三层方案：

1. **预取下一首**（已在 M2 实现）：当前歌开播即对队列后 2 首调 `startDownloadingUbiquitousItem`。顺序播放基本零等待；也避免锁屏自动切到未下载的歌时 App 因不出声被挂起（等待下载期间另申请后台任务时间兜底）。
2. **头部缓存 + 自定义 ResourceLoader**（核心）
   - 文件只要完整在本地出现过一次（播放 / 预取 / 预热），后台截取开头约 1MB 音频存到 `Application Support/HeadCache/`（排除备份）。截取时**跳过 ID3v2 标签**（内嵌封面可能几百 KB），记录文件大小、时长、修改时间。
   - 点一首不在本地的歌：`AVURLAsset` 用自定义 scheme，`AVAssetResourceLoaderDelegate` 呈现“去掉 ID3 的虚拟文件”；开头字节从缓存给 → 立即开播；同时触发系统下载；下载完成后 loader 无缝改从完整文件读。下载慢于播放时只会中途短暂缓冲。
   - 文件大小/修改时间变化 → 缓存作废重建。
3. **一键预热**（设置里）：逐首下载 → 截头部 → 若原本不在本地则 `evictUbiquitousItem` 释放本地副本。全库秒开，只多占头部缓存空间。

播放决策：
1. 完整文件已在本地 → 直接 `AVPlayerItem(url:)`（最稳，开精确时长）。
2. 不在本地但有头部缓存 → ResourceLoader 路径。
3. 都没有 → 触发下载，显示“下载中”，完成后播放。

空间：1MB/首（320kbps ≈ 25 秒，128kbps ≈ 60 秒），1000 首 ≈ 1GB；常量可调。

实现要点：
- 只缓存 mp3 / aac / flac（数据顺序排列，有开头就能起播）；m4a、wav 不缓存。
- 缓存路径用 `playImmediately(atRate:)` 起播，避免 AVPlayer 因“后面数据还没到”判断缓冲不足而不开始。
- 缓存路径不开精确时长（否则要先读完整个文件），VBR 无 Xing 头的 MP3 在这一首里拖动可能略有偏差；下次从本机文件播放就精确了。
- 完整文件下载好后数据源核对文件大小，不一致则丢弃缓存、改从本机文件在当前位置接着播。

需真机验证：
- AVPlayer 起播前是否请求文件末尾（ID3v1 等）——数据源对每个超出头部的请求都会写日志 `等待完整文件：… 请求 x..<y`；若起播前就出现这条，说明需要再缓存末尾几十 KB。
- `evictUbiquitousItem` 对文件选择器授权的外部文件夹是否生效。
- 仅对 MP3 / FLAC 有效；moov 在末尾的 m4a 退化为路径 3。
- 系统设置“蜂窝网络 → iCloud 云盘”关闭时，流量下不会下载完整文件。

## 5. 工程与 CI

- `project.yml`：iOS 16.0、Swift 5、仅 iPhone、竖屏、`com.zcp.sepia`。
- 版本号：`MARKETING_VERSION` 手动维护；`CFBundleVersion` = CI 运行序号；Info.plist 写入 commit（`SepiaCommit`），App 内可见，便于确认装的是哪一版。
- Workflow（`.github/workflows/build.yml`）：
  - 触发：push 到 `main` + 手动触发。
  - `macos-26` runner，固定 `/Applications/Xcode_26.6.app`（升级时改这一行）。
  - 步骤：Core 测试 → `xcodegen generate` → `xcodebuild` 不签名编译 → `codesign -s -` 临时签名并写入 `ci/Sepia.entitlements` → 打包 `Payload/Sepia.app` → 上传 `Sepia-<run>-<commit>.ipa`（`archive: false`，下载即 `.ipa`，不套 zip）。
  - 为什么要临时签名：TrollStore 安装时原样保留二进制自带的 entitlements、不会补。完全不签名的包装上后没有 `application-identifier`，系统文件选择器（iCloud 和「我的 iPhone」都一样）点「打开」后不回调 App（2026-10-27 真机：日志只有“打开文件夹选择器”，没有返回或取消）。备用方案：给 TrollStore 版加 `com.apple.private.security.no-sandbox`，直接读 iCloud 云盘的本地路径，绕过选择器。
- 本机（推送前必跑）：
  - `scripts/test-core.sh`：SwiftPM 因 Command Line Tools 不匹配不可用，改用 `swiftc` 直接编译测试程序。
  - `scripts/typecheck.sh`：用 macOS 26.5 SDK 里的 Mac Catalyst 框架按 `arm64-apple-ios16.0-macabi` 类型检查整个 App，能抓到语法/类型错误和 iOS 17+ API 误用。macOS 27 SDK 的 SwiftUI 把 `@State` 等改成了宏，CLT 缺插件，所以固定 26.5。
- 真机调试：Mac 自带“控制台”App 经 USB 看 `os.Logger` 实时日志（无需 Xcode）；日志另写文件，经“文件”App →“我的 iPhone”→ Sepia 查看（M2 起开启 `UIFileSharingEnabled`）。

## 6. 里程碑

每步都产出可安装 IPA 并在真机验证。

- [x] **M1 骨架 + CI**：空壳 App 显示版本/build/commit；“下载 IPA → 自签 → iOS 16.6.1 启动”链路已在真机验证（2026-10-27）。
M2–M5 代码已在本机完成（2026-10-27），通过 `scripts/test-core.sh` 与 `scripts/typecheck.sh`；等推送后 CI 编译、真机验证再打勾。

- [ ] **M2 音乐库 + 基础播放**：选文件夹、扫描、播放、上下首、进度条、后台与锁屏、恢复上次播放、预取后 2 首、日志。Core 测试接入 CI。
- [ ] **M3 歌词**：SRT/LRC 解析（编码识别、多时间戳、offset、翻译行）+ 网易云式歌词页。
- [ ] **M4 喜欢 + 歌单 + 存储**：音乐文件夹 `sepia-library.json` + 沙盒副本，取较新；读完前禁止修改。
- [ ] **M5 起播优化**：头部缓存 + ResourceLoader、预热、☁ 图标。

### M2 真机验证清单
- [ ] 选 iCloud 文件夹后列出歌曲，子文件夹显示在歌名下方，有歌词的右侧显示引号图标
- [ ] 点歌播放；未下载的歌显示“正在从 iCloud 下载…”，下完自动播放
- [ ] 上一首 / 下一首，播完自动下一首，列表末尾回到第一首
- [ ] 拖进度条松手后跳转，拖动过程中不回弹
- [ ] 锁屏继续播放；锁屏 / 控制中心可暂停、切歌、拖进度；耳机线控可用
- [ ] 拔耳机暂停；来电结束后继续
- [ ] 杀掉 App 重开：停在上次的歌和位置（暂停态）
- [ ] 「文件」App → 我的 iPhone → Sepia 里能看到 sepia.log

### M3 真机验证清单
- [ ] 有 SRT 和 LRC 的歌用 SRT；GBK 编码的中文 LRC 不乱码
- [ ] 播放时当前句居中高亮并自动滚动；双语歌词显示两行
- [ ] 拖动歌词：出现中线、时间和 ▶；点 ▶ 跳到那句并播放
- [ ] 松手 3 秒没操作，中线消失并回到当前句
- [ ] 歌词文件还在 iCloud 时显示“正在加载歌词…”，下完出现

### M4 真机验证清单
- [ ] 播放页 ♥ 和列表长按「喜欢」；「喜欢」页最近喜欢的在前，左滑可移除
- [ ] 新建 / 重命名 / 删除歌单；长按歌曲或播放页按钮「加入歌单」
- [ ] 歌单内点歌，上下首只在这个歌单里切；编辑模式拖动排序、左滑移除
- [ ] 音乐文件夹里出现 `sepia-library.json`；删掉 App 重装、重新选文件夹后喜欢和歌单都还在

### M5 真机验证清单
- [ ] 设置 →「预热全部歌曲」能跑完，进度正常，已缓存数量和大小增加
- [ ] 在「文件」App 里对某首歌「移除下载」后，列表里它没有 ☁（有缓存），点它立即出声，播放页显示“正在后台下载完整文件…”，之后消失
- [ ] 上面这种情况下一直播到 25 秒之后不卡（完整文件已接上）
- [ ] 日志里看起播前有没有 `等待完整文件` 请求文件末尾（见第 4 节）
- [ ] 从没下载过、也没缓存的歌显示 ☁，点了等下载后播放

## 7. 获取 IPA

1. 打开仓库 Actions → 最新一次 “Build IPA” 运行。
2. 在 Artifacts 下载 `Sepia-<run>-<commit>.ipa`（需登录 GitHub）。
3. 用你的自签工具签名安装；保持 Bundle ID `com.zcp.sepia` 不变。
