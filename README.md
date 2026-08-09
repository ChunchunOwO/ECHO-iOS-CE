<p align="center">
  <img src="docs/app-icon.png" width="96" alt="ECHO iPhone app icon" />
</p>

<h1 align="center">ECHO iPhone Community Edition</h1>

<p align="center">
  一款面向 iPhone 的独立音乐播放器，支持连接 <a href="https://github.com/Moekotori/ECHO">ECHO NEXT</a> EchoLink
</p>

<p align="center">
  <strong>简体中文</strong> · <a href="README.en.md">English</a> · <a href="RELEASE_NOTES.md">Release Notes</a>
</p>

> 这是一个非官方社区项目，不隶属于 ECHO NEXT 官方仓库。

> 如果你有所属权、建议或问题反馈，可以在 [ECHO 官方 QQ 群](https://qm.qq.com/q/OdpngxJU86) 联系 @2709128412。

> 本项目定位为独立音乐播放器。EchoLink 是其中一个连接、控制和串流来源，上游兼容会持续同步。

> 如果ECHO NEXT更新了IOS端 我会在此项目标出

> 这个项目是我的第一个作品 做的很烂 感谢理解<3

## ECHO-iOS-CE是什么？

ECHO iPhone 是一个独立的 iPhone 音乐播放器。极简，易用，美观是他的特点。
TA可以播放手机本地音乐、连接 ECHO NEXT，也可以登录网易云音乐，获取安卓PowerAMP曲库等。曲库、搜索、播放列表、歌词和播放控制集中在同一个 App 内。

## 功能亮点

- 播放输出：支持本地、流媒体、控制和串流，一处切换。
- 本地曲库：支持导入、扫描、收藏、最近播放、本地队列、LRC 歌词导入。
- 多来源曲库：支持全部、ECHO、本地和流媒体；本地曲库可按歌曲、专辑、艺术家、格式、收藏和最近播放浏览。
- 网易云音乐：可直连网易云 Web 接口或使用自托管服务，支持二维码登录、账号信息、歌单、搜索和播放。
- 全局搜索：搜索 ECHO 与本地曲库中的歌曲、专辑和艺术家。
- 自建歌单：可创建、重命名、删除、收藏和置顶歌单，也可从 ECHO 或本地曲库加入歌曲。
- EchoLink 配对链接连接：支持 `echo://pair?...` 一键填入。
- 二维码配对：可使用相机扫描，也可以从相册读取二维码。
- 手动局域网连接：Host、Port、Token 会保存到本机，不需要每次重新粘贴配对链接。
- 连接页新增 ECHO 连接开关，默认关闭；关闭时不会轮询电脑端，也不会弹出连接错误。
- 原生页面：播放、曲库、搜索、连接和设置使用 SwiftUI，底部使用原生 TabView；支持系统 Liquid Glass，旧系统保留材质回退。
- 播放页：封面、歌曲信息、tag、进度、播放控制、音量、EQ、歌词、播放列表和输出切换集中在一个播放器视图里。
- 真 DSP：本地 / 串流播放支持 iOS 原生 DSP、EQ 预设和响度归一化。
- EQ 预设：均衡、低频、人声、清晰、暖声、夜间。
- 音量展开条：展开后显示更长的滑条和当前百分比。
- 原生播放列表：支持播放、移除、排序和清空，并显示当前歌单与正在播放的歌曲。
- 歌词模式：支持本地 LRC、EchoLink `/lyrics`、LRCLIB、LrcAPI 和网易云音乐，支持自动滚动与当前歌词高亮。
- 歌词点击跳转：有时间戳的歌词行可以直接 seek。
- 外源数据：歌词优先使用 LRCLIB，封面优先使用网易云音乐；LrcAPI 可补充歌词、封面和艺术家。默认每次显示候选并分别选择字段来源，也可切换为自动匹配或不使用。
- 曲库补图：当前展示的本地与 ECHO 歌曲缺少封面时会尝试外源检索，刷新曲库可重试未命中的歌曲。
- 稳定封面加载：新封面加载成功前保留上一张封面，减少默认封面闪动和空白。
- 滑条断触修复：进度条和音量条拖动时锁住页面手势，避免界面上滑抢触摸。
- 播放控制：上一首、播放/暂停、下一首、单曲循环、播放列表预览。
- 曲库搜索：浏览 PC 本地曲库，并从手机点歌到电脑端播放。
- 输出切换：可本地播放、控制电脑播放，也可在支持时串流到 iPhone。
- 音频信息标签：Local、可串流、WASAPI/ASIO、格式、采样率、位深、码率等。
- 设置页：按功能分组展开，支持语言、默认页面、默认曲库、音频 tag、EQ、响度归一化、外源数据、存储管理等设置。
- 本地持久化：连接信息、设置状态、本地收藏、最近播放和队列都会保存到 App 本地数据。
- 播放保护：拖动进度时不会被状态刷新拉回；切换输出失败时保留当前播放，不会显示错误模式。
- 数据保护：本地扫描失败不会清空收藏、最近播放、歌单或队列；旧连接响应不会覆盖当前连接。
- 等等等功能等你发现~✨

## 环境要求

- Node.js 与 npm
- Expo，通过 `npx expo`
- 本地 iOS 构建需要 macOS + Xcode
- Windows 用户可以通过 GitHub Actions 触发 macOS runner 生成未签名 IPA
- 真机安装需要 Sideloadly、AltStore、Xcode 或其他签名安装方式

## 本地运行

```powershell
npm install
npm run start
```

类型检查：

```powershell
npm run typecheck
```

iOS Expo 导出检查：

```powershell
npx expo export --platform ios --output-dir build\export-check
```

## 连接 ECHO NEXT

连接页默认不会自动连接 ECHO。需要使用电脑端功能时，先打开“启用 ECHO 连接”，再扫描二维码、从相册读取二维码、粘贴配对链接，或手动输入局域网地址。

```text
echo://pair?host=192.168.1.12&port=26789&token=...
```

手动连接字段：

- Host：电脑局域网 IP，例如 `192.168.2.27`
- Port：通常是 `26789`
- Token：从桌面端 EchoLink 配对界面复制

连接信息会保存在本机 AsyncStorage，下次打开 App 不需要重新粘贴配对链接。关闭 ECHO 连接开关后，App 会保留信息，但不会主动连接或弹窗提醒。

如果连接失败，优先检查：

- iPhone 和电脑是否在同一个 Wi-Fi / LAN。
- ECHO NEXT 是否正在运行，EchoLink 是否开启。
- Windows 防火墙是否允许 ECHO NEXT 在专用网络通信。
- Host 是否填写电脑局域网 IP，而不是 `localhost`、虚拟网卡 IP 或公网 IP。
- iOS 是否允许本地网络权限。

## 设置与外源数据

- 连接信息保存在 `src/storage/connectionStore.ts`。
- 设置项通过 App 本地个人数据保存，包括语言、默认页面、默认曲库、音频 tag、EQ、响度归一化、封面背景、ECHO 连接、外源匹配方式和网易云访问方式。
- 本地音乐状态保存在 `src/storage/localMusicStore.ts`，包括收藏、最近播放和本地队列。
- LRCLIB：优先用于获取歌曲歌词等。
- LrcAPI：可补充歌词、封面和艺术家。
- 网易云音乐：中文曲库补充，主要用于封面，也可作为歌词 fallback。
- 即使只有一个候选也会由用户确认；可以分别指定歌词、艺术家和封面来源，也可以选择“不使用”或启用自动匹配。
- 网易云登录凭据保存在 iOS Keychain，普通设置和歌单状态保存在 App 本地数据。

## EchoLink 接口

移动端当前使用：

```text
GET  /echo-link/v1/status
GET  /echo-link/v1/library/tracks?page=1&pageSize=40&q=...
GET  /echo-link/v1/library/albums?page=1&pageSize=40&q=...
GET  /echo-link/v1/library/albums/:albumId/tracks
POST /echo-link/v1/playback/command
POST /echo-link/v1/library/tracks/:trackId/stream
GET  /echo-link/v1/library/tracks/:trackId/lyrics
```

请求头：

```text
Authorization: Bearer <token>
x-echo-link-version: 1
```

## 构建未签名 IPA

iOS 构建仍然依赖 macOS 和 Xcode。Windows 不能直接生成可用 IPA，但可以触发 GitHub Actions。

### GitHub Actions

1. 推送本仓库到 GitHub。
2. 打开 GitHub Actions。
3. 运行 `Build iOS unsigned IPA`。
4. 下载 `ECHO-iPhone-unsigned-ipa` artifact。
5. 使用 Sideloadly、AltStore 或其他方式签名安装。

### 本地 Mac 构建

```bash
bash scripts/build-unsigned-ipa-for-sideloadly.sh
```

输出：

```text
build/ios-unsigned/ECHO-iPhone-unsigned.ipa
```

### Xcode 免费 Apple ID

```bash
bash scripts/build-free-apple-id-with-xcode.sh
```

脚本会打开生成的 Xcode workspace。选择自己的 Apple ID Team，连接 iPhone，然后 Run。

## 资源说明

- `docs/app-icon.png` 是 README 和 Expo 当前共用的应用图标。
- `docs/app-icon.svg` 是同风格的轻量展示版图标。
- `docs/preview.svg` 是 README 顶部 ACG 风格功能预览图。
- `Assets.car` 可以放在仓库根目录，未签名 IPA 脚本会在打包时复制进最终 `.app`。
- 歌曲封面优先使用本地文件或 EchoLink artwork URL；如果没有返回封面或图片加载失败，App 会尝试网易云音乐封面，再保留稳定封面或显示 ECHO 占位。

## 项目结构

```text
App.tsx                         主界面、播放控制、歌词、本地播放、串流和设置
app.json                        Expo iOS 配置
modules/echo-audio-dsp/         iOS 原生 DSP 播放模块
modules/echo-audio-dsp/ios/     SwiftUI 页面、播放器、歌词、EQ 与原生音频实现
src/components/                 App 内部图标组件
src/echoLink/client.ts          EchoLink HTTP 客户端
src/echoLink/types.ts           移动端 EchoLink 类型
src/echoLink/pairing.ts         配对 URI 解析
src/localMusic/                 本地音乐扫描、导入、元数据和歌词
src/storage/connectionStore.ts  本地连接信息保存
src/storage/localMusicStore.ts  本地音乐状态保存
src/storage/settingsStore.ts    设置持久化
src/storage/streamingStore.ts   流媒体偏好与安全会话保存
src/streaming/                  网易云登录、歌单、搜索和播放接口
scripts/                        iOS 构建辅助脚本
.github/workflows/              未签名 IPA 工作流
docs/                           图标、预览图和 README 资产
```

## Release 更新日志

最新更新请看 [RELEASE_NOTES.md](RELEASE_NOTES.md)（已过期）。
