# Sepia 开发计划

极简本地音乐播放器：播放你自己 iCloud Drive 文件夹里的音乐和歌词。

## 0. 已确定的约束

| 项 | 决定 |
|---|---|
| 系统 | 最低 iOS 16.0（测试机 iOS 16.6.1），仅 iPhone，竖屏 |
| Bundle ID | `com.zcp.sepia`，固定不变（重签时保持一致才能覆盖安装、不丢数据） |
| 安装 | CI 产出**无签名** IPA，用户自行自签安装 |
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
- 文件夹选择器 + 书签（iOS 用默认 options，`.withSecurityScope` 是 macOS 专用）
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
│   ├── Info.plist              # 由 XcodeGen 按 project.yml 生成
│   ├── Core/                   # 纯 Foundation 逻辑，本机可用 swiftc 编译测试
│   │   ├── Models.swift        # Song / Playlist / LyricLine
│   │   ├── LyricsParser.swift  # SRT + LRC 解析、编码识别
│   │   ├── LibraryFile.swift   # library.json 编解码与合并
│   │   └── HeadCacheMath.swift # 头部缓存字节范围换算
│   ├── Library.swift           # 文件夹授权、扫描、喜欢、歌单
│   ├── Player.swift            # AVPlayer、队列、锁屏控制
│   ├── HeadCache.swift         # 头部缓存 + ResourceLoader（M5）
│   └── Views/
│       ├── LibraryView.swift   # 全部 / 喜欢 / 歌单
│       ├── PlayerView.swift
│       ├── LyricsView.swift
│       └── SettingsView.swift
├── scripts/test-core.sh        # swiftc 编译并运行 Core 测试（本机与 CI 共用）
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

1. **预取下一首**：当前歌开播即对队列后 2 首调 `startDownloadingUbiquitousItem`。顺序播放基本零等待。
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

需真机验证：
- AVPlayer 起播前是否请求文件末尾（ID3v1 等）——loader 先打日志记录请求范围，必要时再缓存末尾几十 KB。
- `evictUbiquitousItem` 对文件选择器授权的外部文件夹是否生效。
- 仅对 MP3 / FLAC 有效；moov 在末尾的 m4a 退化为路径 3。
- 系统设置“蜂窝网络 → iCloud 云盘”关闭时，流量下不会下载完整文件。

## 5. 工程与 CI

- `project.yml`：iOS 16.0、Swift 5、仅 iPhone、竖屏、`com.zcp.sepia`。
- 版本号：`MARKETING_VERSION` 手动维护；`CFBundleVersion` = CI 运行序号；Info.plist 写入 commit（`SepiaCommit`），App 内可见，便于确认装的是哪一版。
- Workflow（`.github/workflows/build.yml`）：
  - 触发：push 到 `main` + 手动触发。
  - `macos-26` runner，固定 `/Applications/Xcode_26.6.app`（升级时改这一行）。
  - 步骤：Core 测试（M3 起）→ `xcodegen generate` → `xcodebuild` 不签名编译 → 打包 `Payload/Sepia.app` → 上传 `Sepia-<run>-<commit>.ipa`（`archive: false`，下载即 `.ipa`，不套 zip）。
- 本机：SwiftPM 因 Command Line Tools 不匹配不可用，`swiftc` 正常 → Core 测试用 `scripts/test-core.sh`。
- 真机调试：Mac 自带“控制台”App 经 USB 看 `os.Logger` 实时日志（无需 Xcode）；日志另写文件，经“文件”App →“我的 iPhone”→ Sepia 查看（M2 起开启 `UIFileSharingEnabled`）。

## 6. 里程碑

每步都产出可安装 IPA 并在真机验证。

- [ ] **M1 骨架 + CI**：空壳 App 显示版本/build/commit；验证“下载 IPA → 自签 → iOS 16.6.1 启动”链路。
- [ ] **M2 音乐库 + 基础播放**：选文件夹、扫描、播放、上下首、进度条、后台与锁屏。播放来源设计成可替换（为 M5 预留）。
- [ ] **M3 歌词**：Core 解析器 + 测试脚本接入 CI + 网易云式歌词页。
- [ ] **M4 喜欢 + 歌单 + 存储**。
- [ ] **M5 起播优化**：预取 → 头部缓存 → 预热。

## 7. 获取 IPA

1. 打开仓库 Actions → 最新一次 “Build IPA” 运行。
2. 在 Artifacts 下载 `Sepia-<run>-<commit>.ipa`（需登录 GitHub）。
3. 用你的自签工具签名安装；保持 Bundle ID `com.zcp.sepia` 不变。
