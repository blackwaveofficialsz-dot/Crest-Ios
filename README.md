# Crest

Crest 是 BlackWave 的餐饮经营助手客户端，提供账号与工作空间管理、AI 对话和经营分析。本仓库包含 **iOS、Android、HarmonyOS 三套原生工程**，后端服务独立维护。

本文是开发与交接入口，按 2026-10-09 工作区源码、构建配置和现有文档整理。各端的验证结果注明记录日期；本次文档整理没有重新执行三端构建或设备验收。

## 功能与范围

| 模块 | 当前代码覆盖的主要能力 |
| --- | --- |
| 账号 | 手机号识别、密码／验证码登录、注册、找回与修改密码、登录恢复、退出登录 |
| 工作空间 | 个人／企业工作空间切换、加入团队、记忆最近使用的工作空间 |
| AI 对话 | 流式回复、历史会话、搜索、重命名／置顶／删除、Markdown 与结构化结果、复制／分享及回复操作 |
| 经营分析 | 看板、订单、产品、人效、营收报警；日期／门店筛选、趋势与明细、CSV 导出 |
| 个人设置 | 昵称与头像、图片裁剪、主题切换、跟随系统／简体中文／英文 |

经营分析面向企业工作空间，实际可见数据由服务端权限决定。上述为实现范围，各端的完成度和验收范围不同，见下方“多端状态与已知限制”。

iOS 当前源码是 Android、鸿蒙同步时的功能、流程和文案基准；平台原生控件、字体、系统分享和文件选择器允许存在差异。接口能力以实际服务端为准，历史设计方案不能直接视为已上线功能。

## 仓库结构与代码入口

```text
.
├── Crest.xcodeproj/        iOS Xcode 工程
├── Crest/
│   ├── App/               应用入口、环境与方向配置
│   ├── API/               认证、聊天、经营分析接口与分析缓存
│   ├── Session/           登录状态、令牌刷新与 Keychain
│   ├── Models/            数据模型、主题、语言和聊天展示状态
│   ├── Views/             登录、聊天、经营分析等页面
│   ├── Components/        聊天、图表与共享界面组件
│   └── Localizable.xcstrings  共享文案来源
├── CrestAndroid/          Kotlin / Jetpack Compose 工程
│   └── app/src/main/java/com/blackwave/crest/
│       ├── core/          网络、会话、数据模型、安全存储
│       ├── feature/       登录、聊天、经营分析等功能
│       └── ui/            主题、图标、多语言等界面基础能力
├── CrestHarmony/          ArkTS / ArkUI Stage 工程
│   └── entry/src/main/ets/
│       ├── core/          模型、协议、格式化和多语言
│       ├── services/      网络、会话、安全存储和系统能力
│       ├── state/         聊天状态管理
│       ├── components/    原生界面组件
│       └── pages/         登录、主界面和经营分析
├── scripts/               iOS 模拟器同步与聊天展示逻辑检查
└── docs/                  接口设计、实施方案与专项记录
```

| 要了解的内容 | iOS 入口 | Android 入口 | 鸿蒙入口 |
| --- | --- | --- | --- |
| 启动与页面编排 | [CrestApp.swift](Crest/App/CrestApp.swift)、[RootView.swift](Crest/Views/RootView.swift) | [MainActivity.kt](CrestAndroid/app/src/main/java/com/blackwave/crest/MainActivity.kt) | [Index.ets](CrestHarmony/entry/src/main/ets/pages/Index.ets) |
| 登录、续期与空间切换 | [SessionStore.swift](Crest/Session/SessionStore.swift) | [SessionStore.kt](CrestAndroid/app/src/main/java/com/blackwave/crest/core/session/SessionStore.kt) | [Session.ets](CrestHarmony/entry/src/main/ets/services/Session.ets) |
| 接口调用 | [API 目录](Crest/API/) | [ApiClient.kt](CrestAndroid/app/src/main/java/com/blackwave/crest/core/network/ApiClient.kt) | [Api.ets](CrestHarmony/entry/src/main/ets/services/Api.ets) |
| 聊天与流式状态 | [ChatView.swift](Crest/Views/ChatView.swift) | [ChatController.kt](CrestAndroid/app/src/main/java/com/blackwave/crest/feature/chat/ChatController.kt) | [ChatStore.ets](CrestHarmony/entry/src/main/ets/state/ChatStore.ets) |
| 经营分析 | [BusinessAnalyticsView.swift](Crest/Views/BusinessAnalyticsView.swift) | [AnalyticsScreen.kt](CrestAndroid/app/src/main/java/com/blackwave/crest/feature/analytics/AnalyticsScreen.kt) | [AnalyticsPage.ets](CrestHarmony/entry/src/main/ets/pages/AnalyticsPage.ets) |

接手时先沿“应用入口 → 会话恢复 → 登录／主页面 → 接口请求”阅读，再进入负责的功能模块。

## 开发环境

| 平台 | 当前工程配置与工具链 |
| --- | --- |
| iOS | macOS + Xcode；本次查阅环境为 Xcode 26.6，Swift 语言模式为 5.0，部署目标 iOS 17.0。最低可用 Xcode 版本未单独验证 |
| Android | JDK 17、Android SDK 36；最低 API 26，目标 API 36；仓库自带 Gradle Wrapper 8.13，AGP 8.12.0，Kotlin 2.1.20 |
| 鸿蒙 | DevEco Studio 与配套 HarmonyOS SDK；已有构建记录使用 DevEco Studio 26.0.0.851 / SDK 26.0.0.105；编译 SDK 配置为 26.0.0，最低／目标为 HarmonyOS 5.0.0（API 12） |
| 辅助工具 | Node.js / npm 用于 Android 文案同步、鸿蒙离线测试与资源同步；仓库未统一锁定 Node.js 版本 |

请拉取完整仓库：Android 和鸿蒙的文案生成脚本依赖同仓库的 iOS 文案表。测试账号、企业工作空间权限及签名权限由项目负责人提供，不包含在 README 中。

## 运行与构建

以下各平台小节均从仓库根目录开始。构建会下载相应依赖；模拟器安装步骤会更新目标设备上的 Crest 应用。

### iOS

打开工程，选择 `Crest` scheme，并检查 Signing & Capabilities 中的开发团队：

```sh
open Crest.xcodeproj
```

在 Xcode／Simulator 中启动目标模拟器，再执行带签名校验的同步脚本：

```sh
./scripts/sync-simulator.sh
```

- 默认构建 `Debug`，目标模拟器名称为 `iPhone 17 Pro`。
- 脚本负责构建、校验签名标识、安装并启动应用；不会创建或启动模拟器。
- 构建目标由 `SIMULATOR_NAME` 指定，安装目标使用 `simctl ... booted`。运行时只保持目标模拟器一台处于启动状态，并确保名称一致。
- 可用 `SIMULATOR_NAME`、`CONFIGURATION`、`DERIVED_DATA_PATH` 调整目标、配置和构建目录。例如，使用当前登录账号验收经营分析时，可构建 Release 模拟器版本：

```sh
CONFIGURATION=Release SIMULATOR_NAME="iPhone 17 Pro" ./scripts/sync-simulator.sh
```

**不要使用 `CODE_SIGNING_ALLOWED=NO`。** 脚本要求 `application-identifier` 为 `RZA2NW5788.com.blackwave.crest`，以保留 Keychain 所需的应用标识。若交接到其他开发团队，需同步核对工程签名和脚本中的预期标识，并重新验证登录保存与恢复。

Debug 与 Release 的经营分析会话不同，首次运行前请阅读下方“后端与环境配置”。

上传 iOS 测试版本请按 [TestFlight 发布与交接指南](docs/ios-testflight-release.md) 操作，包含账号权限、当前发布待办、Archive 上传、内部／外部测试与审核资料模板。

### Android

使用 Android Studio 打开 `CrestAndroid/`，设置 Gradle JDK 为 17，通过 SDK Manager 安装 SDK 36。SDK 路径由本机 `local.properties` 中的 `sdk.dir` 或 `ANDROID_HOME` 配置，不要提交其他人的本机路径。

```sh
cd CrestAndroid
./gradlew :app:assembleDebug
```

Debug APK 位于 `CrestAndroid/app/build/outputs/apk/debug/app-debug.apk`。连接模拟器或真机后，可在同一目录安装：

```sh
./gradlew :app:installDebug
```

安装后从设备启动 Crest，或直接使用 Android Studio 的 Run。Windows 使用 `gradlew.bat`。正式发布签名未在当前 `app/build.gradle.kts` 中配置，Debug APK 不能作为正式发行包。

### HarmonyOS

使用 DevEco Studio 打开 `CrestHarmony/`，完成 SDK／Hvigor 同步，为开发设备配置签名，再选择 `entry` 运行。详细步骤见 [鸿蒙 README](CrestHarmony/README.md)。

在配置好 Node.js / npm 的终端执行：

```sh
cd CrestHarmony
npm ci
npm test
npm run check:project
npm run build:hap
```

`build:hap` 调用官方 Hvigor 构建 Debug HAP，自动查找命令行 `hvigorw` 或 macOS 默认安装目录 `/Applications/DevEco-Studio.app`。自定义安装位置可通过 `CREST_HVIGORW` 指定官方 `hvigorw` 路径，并配置对应 SDK 环境。

当前未签名产物路径为 `CrestHarmony/entry/build/default/outputs/default/entry-default-unsigned.hap`。离线测试和工程检查不能替代 ArkTS／ArkUI 原生编译；未签名 Debug HAP 也不代表已完成签名、真机或发行验收。

## 后端与环境配置

三端默认服务根地址均为 `https://blackwave.org.cn/yuanji`，接口使用 `/api/v1/...` 路径，例如 `POST /api/v1/auth/login`。这是现有远程服务，客户端操作会使用真实接口；联调前应确认测试账号、工作空间和允许修改的数据范围。

| 平台／用途 | 配置入口 |
| --- | --- |
| iOS 通用接口 | [APIClient.swift](Crest/API/APIClient.swift) 的默认地址；可通过应用进程环境变量 `CREST_API_BASE_URL` 覆盖 |
| iOS 经营分析接口 | [AnalyticsAPI.swift](Crest/API/AnalyticsAPI.swift)；单独使用 `CREST_ANALYTICS_API_BASE_URL`，默认仍为上述远程服务 |
| iOS Debug 分析账号 | `CREST_ANALYTICS_USERNAME` 与 `CREST_ANALYTICS_PASSWORD`，用于建立独立经营分析会话；刷新令牌保存到独立 Keychain service |
| Android | [app/build.gradle.kts](CrestAndroid/app/build.gradle.kts) 的 `API_BASE_URL`，生成到 `BuildConfig`；修改后需重新构建 |
| 鸿蒙 | [Api.ets](CrestHarmony/entry/src/main/ets/services/Api.ets) 的 `API_BASE`；修改后需重新构建 |

iOS 进程环境变量可在本机 Xcode Scheme → Run → Arguments → Environment Variables 中配置。地址应包含 `/yuanji` 等服务前缀，不包含具体 `/api/v1/...` 端点。不要将账号、密码或令牌提交到共享 Scheme、源码或文档。

**iOS Debug 的经营分析当前强制走 `AnalyticsOnlineSession`，与主页登录会话分开；Release 使用当前登录账号与工作空间。** 因此“主页已登录”不保证 Debug 分析页可用。出现“线上经营分析会话已失效”时，检查专用测试账号配置，或使用上述 Release 模拟器流程验收正常登录链路。

切换 iOS 环境时须分别检查通用接口和分析接口。专用 `AnalyticsOnlineSession` 的刷新客户端仍固定使用默认远程根地址，这两个环境变量不构成完整的全局环境切换；切换服务时需核对该刷新链路。

后端源码与部署不在本仓库。历史方案引用独立的 `duizhangAgent` 后端项目，实际仓库地址、维护人、环境划分及接口版本需随交接一并确认。[账号与工作空间接口契约](docs/superpowers/plans/2026-09-14-account-workspaces/01-api-contract.md) 是设计参考，联调时仍需核对服务端实际行为。

## 验证方式

### iOS 独立逻辑检查

在仓库根目录执行以下命令，检查聊天展示状态与 Markdown 缓存的集成，不启动应用或调用后端：

```sh
swiftc -module-cache-path /private/tmp/crest-playback-module-cache \
  Crest/Models/ChatTextPlayback.swift \
  Crest/Components/Chat/MarkdownBlockParser.swift \
  scripts/check-chat-playback.swift \
  -o /private/tmp/crest-chat-playback-check
/private/tmp/crest-chat-playback-check
```

这只是专项检查，不是完整 iOS 回归。实际修改后仍需构建，并在负责的平台验证相关流程。

### Android 自动检查

在 `CrestAndroid/` 执行：

```sh
./gradlew :app:testDebugUnitTest :app:lintDebug
# 需要已连接的模拟器或真机
./gradlew :app:connectedDebugAndroidTest
```

工程已设置 `android.injected.androidTest.leaveApksInstalledAfterRun=true`，用于避免设备测试收尾卸载应用。设备测试仍应使用专用测试设备；已有记录包含一次默认卸载导致本地登录、偏好与缓存清除的情况。

### 鸿蒙检查与设备回归

使用前述 `npm test`、`npm run check:project`、`npm run build:hap`。`npm test` 为离线测试，不连接业务账号；`check:project` 只检查源码与工程约束，不验证 SDK 类型、签名或设备渲染。

三端交接时至少实际走通：登录与重启恢复、切换工作空间、聊天与历史、经营分析的日期／门店筛选、CSV 保存、语言／主题切换、退出后重新进入。短信、修改密码、加入团队、头像上传、删除历史等使用可修改的测试账号验证，并记录实际设备、系统版本、操作及结果。

## 多端状态与已知限制

以下汇总已有记录，**“实现”“编译通过”“设备验证”“可发布”分别记录，不互相替代**。后续验证应更新各端状态文档。

| 平台 | 已有证据 | 仍需完成 |
| --- | --- | --- |
| iOS | 当前业务与界面同步基准；已有聊天展示专项记录 | 按交接版本执行完整业务／设备回归；轻量打字机开关仍关闭 |
| Android | 2026-10-08 记录：Debug 构建、55 项单元测试、8 项设备测试通过；lint 0 错误；五个分析模块做过同条件数据抽样对照 | 真实服务端增量、权限重置与弱网回退；最低版本、真机、大字体、长会话；完整导出／资料写入回归及正式发布准备 |
| 鸿蒙 | 2026-10-08 记录：原生 Debug HAP 构建、129 项离线测试通过；API 26 模拟器完成登录会话、部分资料／历史／回复与页面抽样检查 | API 12 与真机、实时聊天完整状态、经营分析和导出设备验收；分析缓存与精细图表手势；签名及发行准备 |

需要优先关注的差异：

- **鸿蒙尚未迁移经营分析加密缓存与按日增量同步**，目前直接请求服务；图表缩放／平移等交互尚未完整同步。
- Android 的分析缓存已有隔离测试，真实服务端增量命中、删除、权限变化及离线回退仍需专项验收。
- iOS 的 `ChatFeatureFlags.lightweightTypewriter` 当前为 `false`，鸿蒙也保持服务端增量显示；不要因代码存在就将逐字动画视为已启用功能。
- 三端的最低系统、真机、弱网、无障碍和全部业务组合尚不能依据现有抽样记录宣称全部通过。

完整范围与证据见 [Android 同步状态](CrestAndroid/MIGRATION_STATUS.md)和[鸿蒙同步状态](CrestHarmony/MIGRATION_STATUS.md)。

## 维护约定

- **会话与数据隔离**：更改登录、切换工作空间、退出、请求重试或缓存时，验证旧请求不能覆盖新账号／新空间的数据。经营分析需保持用户与工作空间等作用域隔离。
- **凭据存储**：iOS 使用 Keychain；Android 使用 Android Keystore 管理密钥并加密持久化刷新令牌；鸿蒙使用 Asset Store。访问令牌保留在内存，不改为明文落盘。
- **文案同步**：共享界面文案以 `Crest/Localizable.xcstrings` 为来源；不要翻译服务端正文、用户输入或标识符。修改共享文案后，在仓库根目录执行下面的生成命令并检查差异：

```sh
node CrestAndroid/scripts/sync-localizations.mjs
npm --prefix CrestHarmony run sync:strings
```

- **平台变更记录**：同步业务行为时，更新对应 `MIGRATION_STATUS.md`，写明已实现范围、实际验证步骤、剩余差异和证据日期。
- **方案与现状分开**：`docs/superpowers/plans/` 包含历史设计和待实施任务；实现与验收结论以当前代码、测试结果及最新状态记录为准。

## 发布与交接清单

当前三端应用标识均配置为 `com.blackwave.crest`；正式分发前需由发布负责人核对账号归属和最终标识。Android 发布签名、鸿蒙开发／发行签名及商店资料仍需补齐；iOS 模拟器构建成功也不代表已完成 Archive 或商店分发验证。

iOS TestFlight 的具体步骤和发布记录模板见 [iOS 发布指南](docs/ios-testflight-release.md)。首次上传前重点核查隐私清单、加密申报、发行图标和 Release 服务环境。

- [ ] 确定交接分支、提交号和版本；检查未提交／未跟踪文件，确保所需源码、资源及文档均包含在交接版本中。
- [ ] 提供客户端与后端仓库权限、维护人和沟通方式，确认后端部署是否属于本次交接范围。
- [ ] 提供测试账号、企业工作空间权限、服务环境说明；凭据通过安全渠道单独交付。
- [ ] 交接 Apple／Android／鸿蒙相关开发者账号权限、证书或密钥管理方式、发布操作人及有效期。
- [ ] 核对版本号与构建号：iOS 在 `Crest.xcodeproj/project.pbxproj`，Android 在 `CrestAndroid/app/build.gradle.kts`，鸿蒙在 `CrestHarmony/AppScope/app.json5`。
- [ ] 核对隐私政策／用户协议地址及商店材料，记录发行包、安装方式、构建环境与对应提交号，并保留上一发行版本及其源码记录。
- [ ] 整理待办优先级、问题复现步骤、验收范围和下一位负责人；不把历史测试结果当作新交接版本的验收。
- [ ] 由接手同事在自己的电脑上完成运行、一个小修改、相关验证与打包，补充遇到的问题。

## 文档索引

| 文档 | 用途与阅读边界 |
| --- | --- |
| [iOS TestFlight 发布指南](docs/ios-testflight-release.md) | 账号与签名准备、仓库发布待办、Archive 上传、测试分发及交接记录 |
| [Android 同步状态](CrestAndroid/MIGRATION_STATUS.md) | 功能对照、历史验证证据、当前待验收事项 |
| [鸿蒙 README](CrestHarmony/README.md) | 鸿蒙环境、工程结构、构建及运行说明 |
| [鸿蒙同步状态](CrestHarmony/MIGRATION_STATUS.md) | 分阶段验收、设备记录与尚未同步能力 |
| [账号与工作空间方案](docs/superpowers/plans/2026-09-14-account-workspaces/README.md) | 历史业务与数据设计，不能直接作为已实现清单 |
| [账号与工作空间接口契约](docs/superpowers/plans/2026-09-14-account-workspaces/01-api-contract.md) | 接口设计参考，需要与实际后端核对 |
| [实施与验收清单](docs/superpowers/plans/2026-09-14-account-workspaces/02-implementation-and-acceptance.md) | 历史待实施任务及验收设计，不能直接视为已完成结果 |
| [经营分析视觉与交互记录](docs/business-analytics-mobile-design.md) | 设计背景，含模拟内容及后续落地边界 |
| [轻量打字机专项记录](docs/superpowers/reports/2026-09-21-chat-lightweight-typewriter.md) | 关闭状态下的展示逻辑说明与独立检查方式；协议描述具有记录时点限制 |
