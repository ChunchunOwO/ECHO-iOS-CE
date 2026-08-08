---
name: echo-ios
description: Project-specific workflow for maintaining ECHO iPhone. Use when changing this repository's playback, SwiftUI screens, native audio DSP, EchoLink/Poweramp integration, local music behavior, persistence, or Expo bridge code. Prefer native Swift/SwiftUI for new product behavior and use TypeScript only at existing networking, storage, bootstrap, and bridge boundaries.
---

# ECHO iOS Project Skill

## 目标

按本项目已有架构完成小而完整的修改。默认把新的产品行为放在原生 Swift/SwiftUI，尤其是界面、播放、音频处理、播放状态和 iOS 交互；只有当需求明确属于现有 TypeScript 边界时才修改 TS。先理解完整调用链，再在共享拥有者处做最小修改。

## 项目现实

- 这是 Expo 56 + React Native + TypeScript 项目，但当前主要 iOS 页面和播放核心已经迁移到 `modules/echo-audio-dsp/ios/`。
- `App.tsx` 负责启动时加载 JS 本地状态、组装迁移 payload，并挂载 `EchoNativeAppView`。不要继续把新的页面、播放控制或 DSP 逻辑塞进 `App.tsx`。
- iOS 原生模块通过 `modules/echo-audio-dsp/src/index.ts`、`views.tsx` 暴露给 Expo；修改 Swift 暴露属性或事件时，要同步检查 TS 模块包装层。
- `src/` 仍然拥有 EchoLink/Poweramp 协议适配、部分本地存储、歌曲库扫描、流媒体适配和少量纯函数域逻辑。不要为了“统一语言”把这些已稳定的 TS 代码无理由搬到 Swift。
- `app.json` 控制 iOS 权限、后台音频、插件和 URL scheme。涉及能力或权限时先检查这里，而不是直接在代码里绕过配置。

## Swift 优先决策表

默认选择 Swift/SwiftUI：

- 新增或修改 iOS 页面、Tab、Sheet、播放器、歌词、队列、EQ、音量、输出切换、原生动画和可访问性。
- 新增音频解码、DSP、AVAudioSession、Now Playing、后台播放、设备路由或播放恢复行为。
- 修改原生持久化后的状态投影、播放时序、串行任务、异步取消或当前曲目派生状态。
- 需要直接使用 iOS API、Swift Concurrency、SwiftUI 环境值或原生生命周期的功能。

保留在 TypeScript：

- EchoLink HTTP 请求、配对 URI 解析、Poweramp 客户端和网络协议类型。
- AsyncStorage/SecureStore 的现有读写适配，除非需求明确要求迁移到 Keychain 或原生持久化。
- 本地文件扫描、元数据解析、流媒体服务适配，以及已有 Node 测试覆盖的纯函数。
- `App.tsx` 启动迁移和 Expo 入口胶水。

跨边界功能：先确定哪一侧拥有行为，再让另一侧只提供数据或事件。不要在 TS 和 Swift 各维护一份会互相竞争的播放状态。

## 原生文件职责

修改前先用 `rg` 搜索类型、动作字符串、事件名和所有调用者。以下是主要归属：

- `EchoNativeAppStore.swift`：`@MainActor` 应用状态拥有者、播放队列、当前曲目、连接、库视图、外部元数据刷新、播放动作和状态向 SwiftUI 投影。
- `EchoNativeAppStorePayload.swift`：从 JS/Expo payload 解析页面数据、库集合、播放列表、搜索和用户动作；新增 payload 字段时检查解码默认值。
- `EchoNativeCoreTypes.swift`：持久化模型、曲目/专辑/连接/设置/播放模式/播放状态和 Codable 兼容逻辑。新增字段优先使用 `decodeIfPresent` 加默认值。
- `EchoNativePlayerView.swift`：播放器页面、歌词、队列、EQ、音量、输出选择、信号路径、封面和紧凑布局。复用现有 view modifier、颜色、sheet 和标签样式。
- `EchoNativePagesView.swift`：库、搜索、播放列表、连接、设置、配对和页面导航。动作通过现有 `onAction`/payload 通道进入 store。
- `EchoAudioDspModule.swift`：Expo Module 注册、音频引擎、AVAudioSession、Now Playing、远程控制和 DSP 播放状态。不要在 View 中直接操作底层引擎。
- `EchoNativeLocalLibrary.swift`：本地文件导入、扫描、音频文件读取和流缓存。
- `EchoNativeRemoteClients.swift`：EchoLink、Poweramp、NetEase 等远程请求与响应解码；保持认证头和错误映射的一致性。
- `EchoNativeMetadataService.swift`：歌词、封面和外部元数据的合并、去重、时间戳处理。
- `EchoNativePersistence.swift`：原生状态落盘入口。修改持久化流程时必须考虑旧版本数据和失败回滚。
- `EchoNeteaseLoginView.swift`：NetEase 登录 WebView/二维码恢复流程；不要把登录凭据写入普通 UI 状态。
- `src/echoLink/`、`src/storage/`、`src/localMusic/`、`src/streaming/`、`src/playback/`、`src/library/`：只有需求属于 JS 网络、存储或纯函数域时才在这里实现。

## 开发流程

### 1. 定位真实拥有者

先执行类似命令：

```powershell
rg -n "action-name|PropertyName|TypeName|endpoint" App.tsx src modules/echo-audio-dsp/ios
rg -n "func |private func |struct |class |enum " modules/echo-audio-dsp/ios/Target.swift
```

列出调用者、状态来源、动作入口和副作用出口。若多个页面都走同一个 store 方法，在 store 修一次，不在每个页面打补丁。

### 2. 选择实现层

先按“Swift 优先决策表”判断。新 SwiftUI 功能优先接入现有 `EchoNativePagesModel`、`EchoNativePlayerModel`、`EchoNativeAppStore` 和 `onAction`；新 TS 功能优先复用 `src` 现有 client/store/type。没有明确需要时不要新增协议、工厂、服务层或依赖。

### 3. 修改数据和桥接

- 原生模型与 JS payload 同时变更时，先改 `EchoNativeCoreTypes.swift`/payload 解码，再改发送侧。
- 新字段必须允许旧 payload 缺失；使用默认值保持旧安装数据可读取。
- 动作字符串、track key、source 名称和 storage key 都视为兼容性接口。重命名之前搜索全部生产者和消费者。
- 序列化状态不能因为一次扫描、网络、封面或歌词失败而被清空。失败时保留上一份有效状态并只更新错误/加载标记。

### 4. 处理播放和并发

- 让播放状态变更经过 `@MainActor EchoNativeAppStore`；不要从多个 Task 直接竞争修改同一份模型。
- 延迟、歌词、封面、远程库和音频加载任务必须能取消，并在应用新结果前确认结果仍对应当前曲目/请求代数。
- 切换输出、切换来源或加载新曲目失败时保留当前可播放对象，避免先清空 UI 再等待未知结果。
- 改变队列、重复/随机、上一首/下一首时同时检查当前曲目缺失、空队列、边界和自动推进路径。
- 触及 `DspPlaybackEngine`、AVAudioSession 或 Now Playing 时，不要在 SwiftUI View 中复制引擎逻辑；从模块/store 提供状态和动作。

### 5. 保持 SwiftUI 体验

- 复用项目现有的 `echoGlassGroup`、`echoMediumSheet`、颜色、背景和自适应布局工具。
- 同时检查紧凑 iPhone、较宽 iPhone/iPad、浅色/深色和动态字体下的布局；不要用固定宽度遮挡文字或控制。
- 新按钮使用现有 SF Symbols 和 `Label`/accessibility label；动作按钮、菜单、滑杆和 Tab 保持原有语义。
- 中文和英文标签使用项目已有的 `localized` 模式，不要新增孤立的硬编码语言分支。
- 歌词、队列和播放器的加载/空状态/错误状态必须有稳定占位，不要让封面或异步数据加载造成页面跳动。

### 6. 验证

按变更范围执行，不虚报未执行的原生验证：

```powershell
npm run typecheck
npm run test:library
npx expo export --platform ios --output-dir build\export-check
```

- TS、桥接、网络、存储、协议或纯函数：至少运行 `npm run typecheck`；涉及队列/集合/原生契约时追加 `npm run test:library`。
- `App.tsx`、`app.json`、Expo module 或打包配置：追加 Expo export check。
- Swift/SwiftUI、音频、原生模块：在 macOS + Xcode 上构建并运行目标；Windows 环境只能完成静态检查、Node 测试和 Expo 导出，必须在结果中说明 native runtime 未验证。
- 非平凡逻辑改动留下一个最小可运行检查：优先补充现有 `node:test` 或在现有原生契约测试中增加断言，不创建重复测试框架。

## 常见修改模式

### 新增原生页面动作

1. 在 `EchoNativePagesView.swift` 或 `EchoNativePlayerView.swift` 找到现有 View 和 action 字符串。
2. 复用现有模型字段和 `onAction` 载荷格式。
3. 在 `EchoNativeAppStore.swift` 的统一动作处理处实现副作用。
4. 若动作需要持久化，更新 `EchoNativeCoreTypes.swift` 和 `EchoNativePersistence.swift`，保证旧数据默认值。
5. 在原生契约测试中增加一个精确断言，并运行匹配检查。

### 新增网络字段或端点

1. 先定位 `EchoNativeRemoteClients.swift` 或 `src/echoLink/client.ts` 中同类请求。
2. 复用现有 URL 编码、Authorization、版本头、错误转换和分页处理。
3. 只添加最小响应类型；不要为单个 endpoint 建新的通用网络层。
4. 把结果转换为现有 `EchoNativeCoreTrack`/预览类型，避免 UI 同时理解多套模型。
5. 对空响应、非 200、过期 token、取消和部分字段缺失做验证。

### 修改歌曲库或元数据

1. 区分本地、EchoLink、Poweramp 和 streaming source，保持 source-specific 规则。
2. 失败刷新不得清空收藏、最近播放、歌单、队列或已有封面/歌词。
3. 复用现有 dedupe、归一化、集合构建和封面/歌词优先级。
4. 关注当前曲目 key、streaming snapshot、播放历史和远程队列是否同步。
5. 运行集合、队列和 native-core 测试。

### 修改 Expo/JS 启动桥

1. 只在 `App.tsx` 做启动加载、迁移和模块挂载；不要重新实现原生页面。
2. 保持 `Promise.all` 加载顺序和默认连接/设置结构。
3. 更新 payload 时同时检查 native decoder 的兼容默认值。
4. 运行 typecheck、library tests 和 Expo export。

## 不要做的事

- 不要把 SwiftUI 页面重新写成 React Native 页面，只因为某个局部改动从 TS 开始。
- 不要引入新的 UI、状态管理、网络或音频依赖来解决已有工具可以完成的问题。
- 不要删除或重置用户已有的连接、收藏、最近播放、歌单和队列来“修复”加载错误。
- 不要把 token/cookie 放进普通日志、可见 UI 或普通明文配置；沿用现有 SecureStore/Keychain 边界。
- 不要在没有调用者、兼容性和测试依据时做大规模重命名或文件拆分。
- 不要声称 Windows 上完成了 Xcode、AVAudioSession、后台播放或真实设备验证。

## 完成报告

结束时只说明：改了哪些文件、为什么归属 Swift 或 TS、运行了哪些命令、哪些原生验证因环境未完成。若没有必要的代码变更，直接报告“仅完成 skill 创建与项目验证”，不要为了展示 skill 而制造功能改动。
