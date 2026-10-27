# Sepia

极简的 iOS 本地音乐播放器：播放你自己 iCloud 云盘文件夹里的音乐和歌词。不接入任何音乐平台，App 本身不发任何网络请求。

- 最低 iOS 16.0，仅 iPhone
- 由 GitHub Actions 编译出**未签名**的 IPA，自行签名安装
- 零第三方依赖（SwiftUI + AVFoundation）

## 功能

- 选择 iCloud 云盘里的一个文件夹作为曲库，递归扫描子文件夹
- 播放 / 暂停、上一首 / 下一首、拖动进度条、列表循环
- 后台播放，锁屏、控制中心和耳机线控
- 同步歌词：支持 SRT 和 LRC，网易云式拖动歌词（拖动出现中线和 ▶，点 ▶ 跳到那句）
- 喜欢（♥）和自定义歌单
- 起播缓存：每首歌在本机保留开头约 1MB，歌不在本机时也能立即起播，同时在后台下载完整文件

## 准备音乐文件夹

```
iCloud 云盘/Music/
├── 古风/
│   ├── 白囍.mp3
│   ├── 白囍.lrc        ← 和歌曲同名即可自动匹配
│   └── 残妆.mp3
├── 晴天.flac
├── 晴天.srt           ← 同名时 SRT 优先于 LRC
└── sepia-library.json ← App 自动生成，保存喜欢和歌单
```

- 音乐：mp3、m4a、flac、wav、aac
- 歌词：`.srt` / `.lrc`，编码 UTF-8、UTF-16 或 GBK 都可以；时间相同的第二行（或 SRT 一条字幕里的第二行）显示为翻译
- `sepia-library.json` 存在音乐文件夹里，删掉 App 重装后重新选择同一个文件夹，喜欢和歌单都会恢复

## 安装

1. 打开仓库的 [Actions](https://github.com/zcp1997/sepia-music-player/actions) → 最新一次成功的 **Build IPA**
2. 在页面底部 Artifacts 下载 `Sepia-<序号>-<commit>.ipa`（需要登录 GitHub）
3. 用你的自签工具签名安装。**保持 Bundle ID `com.zcp.sepia` 不变**，这样是覆盖安装，App 里的数据不会丢

App 启动页和「设置」里显示 `v版本 (构建序号) · commit`，用来确认装的是哪一版。

## 使用

1. 首次打开点「选择文件夹」，进入音乐文件夹后点右上角「打开」
2. 点歌播放；长按歌曲可「喜欢」或「加入歌单」
3. 底部迷你播放条点开是播放页：上下拖动歌词浏览，点 ▶ 跳到那句
4. 设置 →「预热全部歌曲」：逐首截取开头做缓存，之后即使系统把文件从本机释放了也能秒开

列表右侧图标：♥ 已喜欢、引号 有歌词、☁ 不在本机也没有缓存（点了要先等下载）。

## 排查问题

日志在「文件」App → 我的 iPhone → Sepia → `sepia.log`。也可以把手机用 USB 连上 Mac，在 Mac 自带的「控制台」App 里看实时日志（子系统 `com.zcp.sepia`）。

## 开发

本机不需要 Xcode，编译以 CI 为准。推送前在本机跑两个脚本：

```bash
scripts/test-core.sh
```

```bash
scripts/typecheck.sh
```

- `test-core.sh`：把 `Sepia/Core`（纯 Foundation 逻辑：扫描、歌词解析、歌单数据、缓存计算）和 `Tests/CoreTests` 编译成命令行程序运行，CI 里也会先跑它
- `typecheck.sh`：借 macOS SDK 里的 Mac Catalyst 框架，按 iOS 16 把整个 App 编译到 SIL 阶段，能抓到类型错误和 iOS 17+ API 误用
- 工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 按 `project.yml` 生成，`.xcodeproj` 不入库
- 图标由 `scripts/make-icon.swift` 生成

设计决定、实现细节和真机验证清单见 [PLAN.md](PLAN.md)。
