# Crest 移动端研发交接文档

交接日期：2026-10-12（北京时间）

覆盖范围：Crest 的 iOS、Android、HarmonyOS 三个原生客户端

交接目的：让接手人员能够定位代码、搭建环境、联调接口，并按已知问题完成验收和发布。

## 1. 接手时先确认的状态

Crest 已具备登录与工作空间、AI 对话、经营分析、个人资料、主题和语言设置等主要功能。iOS 是目前三端功能与文案对齐的参考；Android、HarmonyOS 分别使用原生技术实现，并非网页套壳。

**三个客户端尚不能据此认定全部具备正式发布条件，也不能把后端实时订单能力直接等同于移动端当日实时看板。** 当前需要优先掌握四点：

1. 经营分析默认与自定义日期均以昨天为上限；趋势请求存在 `include_current=false`。若交付目标包含今天的实时营业数据，三端还需要联合后端改造与验收。
2. iOS Debug 经营分析使用独立测试会话，Release 才使用当前登录用户和工作空间。联调时应先排除这一差异。
3. Android 已接入加密分析缓存和按日增量；HarmonyOS 尚未实现对应缓存、增量能力，真实接口和真机验收也不完整。
4. 本次复跑 iOS 对话展示自检失败：测试要求 600ms 收尾，实现为 10 秒。该逐字展示功能默认关闭，不能把此结果描述成现有聊天主链路已发生故障，也不能把该项自检标为通过。

### 代码交付基线

| 项目 | 当前基线 |
| --- | --- |
| GitHub 仓库 | [blackwaveofficialsz-dot/Crest-Ios](https://github.com/blackwaveofficialsz-dot/Crest-Ios)；名称包含 Ios，实际含三端 |
| 本机目录 | `/Users/blackwave/Documents/Crest` |
| 交接分支 | `codex/pending-changes-20261012` |
| 提交 | `27b449c0e344cea2e7e4a2b515de1f490afe9a7a` |
| 提交说明 | `feat(harmony): refine chat UI and preserve design deliverables` |
| 分支检查 | 本机 HEAD 与 `origin/codex/pending-changes-20261012` 跟踪引用一致，ahead / behind 均为 0 |
| 后端仓库 | [blackwaveofficialsz-dot/duizhangAgent](https://github.com/blackwaveofficialsz-dot/duizhangAgent)；独立维护与发布 |
| 版本范围 | 本文核对本地交付代码；服务器当前版本、GitHub 合并状态及商店发布状态需从对应发布记录确认 |

本次新增交接文档前，Crest 没有已跟踪文件的未提交修改；仍有少量未跟踪视频、字体缓存、文档渲染中间文件。它们不作为可复现构建的必要输入。此前清理过未跟踪截图与日志，旧迁移记录中的部分 `work/` 证据路径可能已失效；验收时应重新保存证据。

## 2. 仓库导航与业务入口

从仓库根目录阅读 [README](../../../README.md)，再按平台进入工程。建议克隆完整仓库，Android、HarmonyOS 的文案同步脚本依赖 iOS 文案文件。

| 目录 | 作用 |
| --- | --- |
| `Crest/`、`Crest.xcodeproj/` | iOS SwiftUI 源码与 Xcode 工程 |
| `CrestAndroid/` | Kotlin / Jetpack Compose 原生 Android 工程 |
| `CrestHarmony/` | ArkTS / ArkUI Stage 原生 HarmonyOS 工程 |
| `docs/` | 设计说明、账号接口约定、发布指引、实施与验证记录 |
| `scripts/` | iOS 模拟器安装脚本、聊天展示独立自检 |
| `output/`、`work/` | 部分已跟踪设计成果，以及本机中间产物；是否交付以 Git 跟踪清单为准 |

### 主要代码位置

以下 Android 路径以 `CrestAndroid/app/src/main/java/com/blackwave/crest/` 为前缀，HarmonyOS 路径以 `CrestHarmony/entry/src/main/ets/` 为前缀。

| 职责 | iOS（仓库相对路径） | Android | HarmonyOS |
| --- | --- | --- | --- |
| 启动与根页面 | `Crest/App/CrestApp.swift`、`Crest/Views/RootView.swift` | `MainActivity.kt`、`CrestApp.kt` | `entryability/EntryAbility.ets`、`pages/Index.ets` |
| 登录态、工作空间 | `Crest/Session/SessionStore.swift` | `core/session/SessionStore.kt` | `services/Session.ets` |
| 令牌安全存储 | `Crest/Session/KeychainStore.swift` | `core/security/SecureTokenStore.kt` | `services/TokenStore.ets` |
| 通用网络 | `Crest/API/APIClient.swift` | `core/network/ApiClient.kt` | `services/Api.ets` |
| 对话协议与状态 | `Crest/API/ChatAPI.swift`、`Crest/Views/ChatView.swift` | `feature/chat/ChatController.kt` | `state/ChatStore.ets` |
| 经营分析 | `Crest/API/AnalyticsAPI.swift`、`Crest/Views/BusinessAnalyticsView.swift` | `feature/analytics/AnalyticsScreen.kt`、`AnalyticsData.kt` | `pages/AnalyticsPage.ets`、`core/Analytics.ts`、`core/Dates.ts` |
| 分析缓存 | `Crest/API/AnalyticsCache.swift` | `feature/analytics/AnalyticsSnapshotCache.kt`、`AnalyticsDailyCache.kt`、`AnalyticsTrendLoader.kt` | 尚无对等实现 |

### 主要功能完成边界

| 功能 | 现有能力 | 接手时应注意 |
| --- | --- | --- |
| 账号 | 手机号识别、密码/验证码登录、注册、找回/修改密码、恢复与退出 | 短信、密码修改、过期并发和异常恢复需使用受控测试账号验收 |
| 工作空间 | 个人/企业空间、加入团队、记忆最近空间 | 企业和门店权限由服务端决定；空间切换必须防止旧请求回写 |
| AI 对话 | 流式回复、历史搜索、固定、重命名、删除、Markdown、结构化内容、消息操作 | 断线重放、停止、失败终态、审批和长会话需要三端联调 |
| 经营分析 | 看板、订单、产品、人效、营收报警；筛选、趋势、详情、CSV | 已有页面不代表今天数据已可用；金额、权限和缓存必须一起验收 |
| 资料与外观 | 头像选择/裁剪、昵称、浅深色、系统/中文/英文 | 真机图片方向、上传回读、大字体和横竖屏尚需覆盖 |
| 系统推送、深链接 | 当前交接基线未建立业务接入链路 | 如后续需要应单独定义需求，不纳入已完成范围 |

## 3. 开发环境与启动

### iOS

工程为 `Crest.xcodeproj`，Scheme / Target 均为 `Crest`；最低 iOS 17.0，Swift 语言设置 5.0，支持 iPhone 与 iPad。本次本机工具为 Xcode 26.6（17F113），不据此宣称其他 Xcode 版本已通过兼容验证。

用 Xcode 打开工程、选择有效开发团队和目标设备后运行。已有模拟器快捷脚本，在仓库根目录执行：

```sh
./scripts/sync-simulator.sh
```

默认 Debug、`iPhone 17 Pro`，可用 `CONFIGURATION`、`SIMULATOR_NAME`、`DERIVED_DATA_PATH` 覆盖。执行前启动目标模拟器，并保持只启动一个：脚本按名称构建，但安装和启动使用 `booted`。

脚本要求签名开启，并校验 `RZA2NW5788.com.blackwave.crest`。更换 Apple 开发团队时，需要同时调整工程签名与脚本校验，并回归 Keychain 登录恢复；不要用关闭签名绕过。TestFlight 使用 Release Archive，不能用此模拟器脚本替代，详见 [iOS 发布指引](../../ios-testflight-release.md)。

### Android

使用 Android Studio 打开 `CrestAndroid/`，准备 JDK 17 与 Android SDK 36，设置本机 SDK 位置。`local.properties` 中的个人路径不应进入共享交付配置。

| 配置 | 当前值 |
| --- | --- |
| Gradle / AGP / Kotlin | 8.13 / 8.12.0 / 2.1.20 |
| compileSdk / targetSdk / minSdk | 36 / 36 / 26 |
| applicationId | `com.blackwave.crest` |
| versionName / versionCode | `1.0.0` / `1` |

在 `CrestAndroid/` 执行：

```sh
./gradlew :app:assembleDebug
./gradlew :app:installDebug
```

第二条命令需要连接设备或启动模拟器。Debug APK 位于 `app/build/outputs/apk/debug/app-debug.apk`。当前 `app/build.gradle.kts` 未配置正式发行签名；编译 Debug 成功不代表可直接发布商店。

### HarmonyOS

使用 DevEco Studio 打开 `CrestHarmony/`，同步依赖、配置 SDK 与设备开发签名，再运行 `entry`。工程 `compileSdkVersion=26.0.0`，最低兼容和目标为 `5.0.0(12)`；历史验证主要为 API 26 模拟器，API 12 最低版本与真机仍待验证。

离线检查和原生构建在 `CrestHarmony/` 执行：

```sh
npm ci
npm test
npm run check:project
npm run build:hap
```

`npm` 用于测试和辅助脚本；原生 HAP 仍由 DevEco / Hvigor 构建。脚本查找官方 `hvigorw`，支持 `CREST_HVIGORW` 指定路径，也支持默认 macOS DevEco 安装位置。当前命令固定构建 Debug；典型输出为 `entry/build/default/outputs/default/entry-default-unsigned.hap`，安装真机还需要有效签名。

本次离线检查使用 Node v26.0.0、npm 11.12.1；项目测试依赖 TypeScript 5.9.3。这是本次复现环境，不代表已验证所有 Node 版本或可替代 DevEco 自带工具链。

## 4. 服务地址、账号和环境切换

三端默认服务根地址为 `https://blackwave.org.cn/yuanji`；业务接口继续拼接 `/api/v1/...`。例如密码登录地址为 `https://blackwave.org.cn/yuanji/api/v1/auth/login`。

| 平台/用途 | 配置位置与方式 | 关键限制 |
| --- | --- | --- |
| iOS 通用 API | `Crest/API/APIClient.swift`；进程变量 `CREST_API_BASE_URL` | Xcode Run 环境变量不会自动成为分发包配置 |
| iOS 经营分析请求 | `Crest/API/AnalyticsAPI.swift`；`CREST_ANALYTICS_API_BASE_URL` | 与通用 API 分开配置 |
| iOS Debug 分析身份 | 同文件中的 `AnalyticsOnlineSession`；独立 Keychain 和测试账号环境变量 | 当前内部认证客户端仍固定指向默认服务地址，不能认为两个 Base URL 变量已覆盖全部认证链路 |
| Android | `CrestAndroid/app/build.gradle.kts` 的 `API_BASE_URL` → `BuildConfig.API_BASE_URL` | 改后重新构建 |
| HarmonyOS | `CrestHarmony/entry/src/main/ets/services/Api.ets` 的 `API_BASE` | 改后重新构建 |

**iOS 分析联调常见误区：** Debug 的分析身份可能不同于首页登录身份；也可能出现首页已登录、分析却提示测试会话失效。Release 使用正常登录会话，正式权限验收应使用 Release 和有明确企业、门店范围的测试账号。Debug 所需 `CREST_ANALYTICS_USERNAME` / `CREST_ANALYTICS_PASSWORD` 仅由负责人通过受控渠道配置，不写入共享 Scheme、文档或仓库。

刷新令牌分别由 iOS Keychain、Android Keystore 保护的存储、HarmonyOS AssetStore 保存；访问令牌以会话内存为主。更换应用签名、应用标识或清除应用数据后，需要回归登录恢复；不能把旧设备登录成功当作新安装包验收。

## 5. 前后端接口与必须保留的约定

以下是移动端现有调用入口，路径均相对服务根地址。字段和行为以对应 API 实现及后端当前契约为准；旧 [账号与工作空间方案](../plans/2026-09-14-account-workspaces/01-api-contract.md) 可辅助理解，不能单独证明服务已上线。

| 场景 | 主要接口 |
| --- | --- |
| 账号与登录 | `/api/v1/auth/phone-status`、`login`、`verifications`、`login/code`、`personal-register` |
| 会话恢复、退出 | `POST /api/v1/auth/refresh`、`POST /api/v1/auth/logout` |
| 工作空间 | `GET /api/v1/auth/workspaces`、`POST /api/v1/auth/workspaces/switch`、`POST /api/v1/auth/accept-invite` |
| 资料和密码 | `/api/v1/auth/profile`、`profile/avatar`、`change-password`、`reset-password` |
| 历史会话 | `GET /api/v1/sessions`；按会话 ID 获取、PATCH 更新、DELETE 删除 |
| 流式对话 | `POST /api/v1/agui/runs`，使用 SSE 接收 AG-UI 事件 |
| 停止、审批 | `POST /api/v1/agent-runs/cancel`、`POST /api/v1/agent-runs/approve-action` |
| 分析与权限范围 | `GET /api/v1/analytics/operations/overview`、`operations/products`、`operations/labor`、`revenue-alerts`、`store-scope-tree` |
| 趋势 | `GET /api/v1/analytics/trends/revenue`、`products/trend` |
| 趋势增量 | `POST /api/v1/analytics/trends/revenue/delta`、`products/trend/delta`；iOS / Android 已接入 |

接手后的修改应保留以下约定，并纳入测试：

- 登录、刷新、工作空间切换沿用现有移动会话协议；业务请求使用访问令牌，不把刷新令牌当作普通业务鉴权令牌。
- 用户、工作空间和门店权限由服务端验证。账号/工作空间变化后，清除当前展示与对应缓存状态，阻止旧请求迟到结果覆盖新范围。
- AG-UI 事件按 `threadId`、`runId`、`eventId`、`sequence` 校验和去重；重连沿用运行及游标，避免因网络重试创建第二次业务执行。
- `RUN_ERROR` / 失败是终态。成功、失败、停止、切换会话和退出页面都应结束上游流与展示状态，不能接受终态后的迟到文本。
- 审批继续使用服务端已有运行和动作身份；不能由客户端或模型自行扩展企业、门店或副作用授权。
- 业务日期按 `Asia/Shanghai` 解释，与设备所在时区无关。金额尽量展示后端确定性计算结果；不要在客户端自行把推送、同步、销售和退款数据相加形成另一套财务口径。
- 表格预览不等于完整明细。复制、导出、问答统计的字段范围和精度需分别验收；HarmonyOS 的数值表示与 iOS Decimal 存在极端精度差异，不能宣称全量金额已逐项一致。

## 6. 经营分析与当日实时数据

### 当前实现

| 项目 | iOS | Android | HarmonyOS |
| --- | --- | --- | --- |
| 日期范围 | 昨日、近 7 天、本月、上月；上限昨日 | 同左，按北京时间 | 同左，按北京时间 |
| 页面更新 | 进入/切换条件加载、主动刷新 | 条件变化加载、按钮/下拉刷新 | 页面/条件加载、主动刷新 |
| 本地分析存储 | SQLite 中保存加密载荷；快照及按日事实 | Keystore 保护的加密文件；快照及按日事实 | 暂无对等持久缓存 |
| 增量协议 | 营收、产品趋势已接入 | 已接入，有缓存与作用域测试 | 尚未接入 |
| 缓存时效 | 持久快照保留 30 天、日事实 365 天 | 快照新鲜期 5 分钟、保留 30 天；日事实 365 天 | 直接请求 |

缓存保留期限不等于数据实时性承诺。当前基线没有经过“订单推送到达后，三个移动端自动更新今天指标”的完整验收。

### 若要交付当日实时看板，接手团队需要完成

1. **确认后端已发布能力。** 核对正式订单更新、退款规则、汇总刷新和当天未结束数据接口；以实际部署版本和接口结果为准。
2. **统一三端日期与请求。** 增加今天/当日入口，调整日期上限、趋势的 `include_current` 以及适用的增量参数，回归月初、跨日和未来日期限制。不能只改一个日期控件。
3. **明确新鲜度。** 当前日缓存应识别数据版本/更新时间，区分本地缓存、最新成功结果和加载失败；不要让旧快照伪装成最新数据。
4. **设置有边界的刷新。** 复用现有查询与增量接口，优先合并重复请求；如新增自动刷新，仅在前台相关页面启用，退后台/切换范围立即停止，并支持失败退避。刷新周期与后端成本、产品时效目标一起确定。
5. **按相同条件对账。** 三端和 Web 使用同企业、门店、日期、权限及接口版本，核对订单数、营业额、净实收、退款与 CSV；推送/同步去重及金额计算留在后端。

建议先交付今天的核心指标与明确更新时间，再根据真实请求量补齐 HarmonyOS 缓存、趋势增量和更复杂交互。以上是后续工作，不属于本文已实施内容。

## 7. 验证结果与复现方法

### 本次交接复跑（2026-10-12）

| 检查 | 结果 | 能证明的范围 |
| --- | --- | --- |
| HarmonyOS `npm test` | **131 通过，0 失败** | 离线契约、状态、传输及相关逻辑测试 |
| HarmonyOS `npm run check:project` | **通过，检查 26 个源文件** | 相对导入、清单、权限等项目检查；不验证 ArkUI DSL、SDK 类型、HAP 签名或设备行为 |
| iOS 聊天展示独立脚本编译 | **通过** | 对应模型和解析器可编译 |
| iOS 聊天展示独立脚本执行 | **失败** | 第 27 行附近“成功后最多保留 600ms 展示尾巴”断言触发；后续断言未执行 |

iOS 失败的直接原因：`scripts/check-chat-playback.swift` 在结束后约 600ms 检查全文，而 `Crest/Models/ChatTextPlayback.swift` 的 `finish(at:)` 使用 `time + 10.0`。应先确认预期展示时长，再统一实现、测试和说明并完整回归；不要为了变绿直接删除断言。`ChatFeatureFlags.lightweightTypewriter` 当前为 `false`。

本次没有重新进行三端完整原生构建、真机回归或生产业务写入。下列历史结果保留来源和日期，不能替代当前发行包验收：

| 平台 | 仓库已有验证记录 | 仍未覆盖 |
| --- | --- | --- |
| Android | [迁移状态](../../../CrestAndroid/MIGRATION_STATUS.md)，2026-10-08：Debug 构建、55 项单元测试、8 项设备测试通过；lint 0 错误、16 警告、3 提示；五个分析模块抽样与 iOS 对照、订单 CSV 保存验证 | 最低版本与真机、全部字段组合、真实增量删除/权限变化、弱网回退、完整账号变更流程 |
| HarmonyOS | [迁移状态](../../../CrestHarmony/MIGRATION_STATUS.md)，2026-10-09：存在原生 Debug HAP、API 26 模拟器安装启动和部分登录/资料/历史验收记录 | API 12、真机、正式签名、完整流式与审批、真实经营分析和导出；最新固定状态改动尚缺实际写入闭环验收 |
| iOS | 现有功能参考基线；[逐字展示说明](2026-09-21-chat-lightweight-typewriter.md)、[发布指引](../../ios-testflight-release.md) 可用于定位 | 本次不具备全套回归、TestFlight 安装及性能验收证据；独立展示自检存在上述失败 |

### 常用验证命令

在 `CrestAndroid/`：

```sh
./gradlew :app:testDebugUnitTest :app:lintDebug
./gradlew :app:connectedDebugAndroidTest
```

设备测试需要可用设备。项目设置了 `android.injected.androidTest.leaveApksInstalledAfterRun=true`，避免测试收尾自动卸载造成登录/本地数据丢失；接手时保留并检查实际行为。

在仓库根目录复现 iOS 展示自检：

```sh
swiftc -module-cache-path /private/tmp/crest-playback-module-cache \
  Crest/Models/ChatTextPlayback.swift \
  Crest/Components/Chat/MarkdownBlockParser.swift \
  scripts/check-chat-playback.swift \
  -o /private/tmp/crest-chat-playback-check
/private/tmp/crest-chat-playback-check
```

HarmonyOS 使用第 3 节命令。当前已知 iOS 脚本会触发上述断言，不应将“编译通过”记录成“自检通过”。

## 8. 待办优先级与完成标准

优先级用于接手排序，具体负责人由团队指定。功能目标相关项与正式发布必需项分别验收。

| 优先级 | 工作 | 完成标准 |
| --- | --- | --- |
| P0：交付前 | 确定发行分支、后端版本、受控测试账号及企业/门店权限 | 三端能复现同一组授权数据；有明确版本记录 |
| P0：发布前 | 三端签名与发行包、隐私材料、发行环境核验 | 有效签名安装包实际安装；不依赖开发机调试会话；发布检查有记录 |
| P1 | 修复 iOS 展示自检与实现的时长不一致 | 确认预期后脚本全项通过，验证开关关闭与启用的不同路径 |
| P1：如要求实时营业 | 今天日期、当前日数据、刷新与缓存一致性 | 真正推送带来正式订单与汇总变化后，移动端按约定时效更新；订单/金额/退款与同口径接口一致 |
| P1 | 三端流式对话和会话隔离回归 | 断网重连不重复执行；失败/取消不继续展示；切账号/空间无串数据 |
| P1 | HarmonyOS 真实功能闭环 | 固定/取消固定、改名、头像上传回读、分析数据、CSV、审批等受控场景完成真机验收 |
| P2 | HarmonyOS 分析缓存与增量 | 复用服务端协议；证明命中、重置、删除、权限变化、失败回退及资源释放 |
| P2 | Android 增量在线验收、三端长会话与设备覆盖 | 真实服务端变化正确合并；最低版本、大字体、横竖屏、前后台均有记录 |
| P2 | HarmonyOS 图表缩放/平移及交互差异 | 按产品确认的原生体验验收，不以截图相似代替手势验证 |

性能验收应至少记录长会话、跨月分析、多门店筛选下的请求次数、响应体量、加载延迟、内存与前后台行为。当前没有覆盖三端的真实压测数据，不能承诺高并发或仅凭模拟器短测认定无资源风险。

## 9. 发布与账号资料交接

三端应用标识均为 `com.blackwave.crest`，但 Apple、Android、华为的开发者账号、证书和发布资产分别管理。**GitHub 仓库转到新账号，不会自动转移应用商店所有权和签名资产。**

| 平台 | 当前代码配置 | 发布前事项 |
| --- | --- | --- |
| iOS | Team `RZA2NW5788`，版本 `1.0`，Build `3` | 确认开发者团队/App Store Connect 权限、有效签名、后台最新构建号；Release Archive 与实际安装验收 |
| Android | `1.0.0` / `1`，正式签名未在工程配置 | 确认发行 keystore/alias、保管与备份、目标商店、升级兼容和签名产物 |
| HarmonyOS | `1.0.0` / `1000000`，当前辅助脚本输出 Debug HAP | 确认华为开发者项目、发布证书/描述文件、正式构建与真机安装 |

iOS 当前源码未找到 `PrivacyInfo.xcprivacy`；既有发布指引还记录了图标 alpha、加密申报及 Release Info.plist 核验事项。Debug 引用 `Crest/Info.plist`，Release 使用自动生成配置，因此只修改调试 plist 不足以证明发行包生效。发布负责人应按实际应用行为及发布时的平台规则核对，不能把这些历史记录当作已经修复。

交接时应单独提供：开发者平台和仓库权限、签名资产保管人、受控测试账号、后端环境负责人、隐私/用户协议地址、审核所需访问条件、历次发行包与符号文件、故障联系人。本文不保存密码、验证码、刷新令牌、私钥或生产订单明细。

每次发行记录提交号、三端版本号、后端版本、配置差异和验收结果。保留上一个可用发行包及符号文件；回退方式按目标分发渠道处理，不能假设所有设备允许直接降级安装。涉及本地缓存或安全存储格式变化时，要同时验证升级和恢复登录。

## 10. 接手验收清单

- [ ] 从交付提交完整克隆仓库，三端开发环境与 Debug 构建可复现。
- [ ] 明确服务地址，确认 iOS Debug 独立分析会话与 Release 正常会话差异。
- [ ] 使用受控账号完成登录、冷启动恢复、过期刷新、退出、个人/企业空间切换。
- [ ] 三端同企业、同门店、同日期核对五个分析模块与 CSV，明确哪些场景只支持历史日期。
- [ ] 受控对话覆盖成功、失败、停止、重连、审批、长回复和账号切换，不留下活动请求或重复副作用。
- [ ] 验证头像、语言、主题、大字体、横竖屏及弱网；HarmonyOS 覆盖真实上传回读和最低版本。
- [ ] iOS 展示自检的已知失败已处理或作为明确遗留项签收，记录功能开关状态。
- [ ] 若交付包含当日实时看板，完成第 6 节全链路验收并记录更新时间与刷新成本。
- [ ] 三端签名、商店账号权限、发行环境和隐私材料已交接；实际发行包安装验收通过。
- [ ] 保存新的测试报告和必要截图，记录未解决问题、负责人和交付版本。

## 11. 继续阅读

- [项目 README](../../../README.md)：日常开发总入口和工具链说明。
- [Android 同步状态](../../../CrestAndroid/MIGRATION_STATUS.md)：功能差异、历史测试结果与专项待验收项。
- [HarmonyOS README](../../../CrestHarmony/README.md) 与 [同步状态](../../../CrestHarmony/MIGRATION_STATUS.md)：ArkUI 工程、原生构建及逐批实现边界。
- [iOS TestFlight 发布指引](../../ios-testflight-release.md)：签名、归档、发行包与发布前核验。
- [经营分析设计](../../business-analytics-mobile-design.md)：页面和指标设计背景，实施状态仍以代码为准。
- [账号与工作空间方案](../plans/2026-09-14-account-workspaces/README.md)：接口和流程背景。

文案源为 `Crest/Localizable.xcstrings`；后续文案变更后，使用 `node CrestAndroid/scripts/sync-localizations.mjs` 和 `npm --prefix CrestHarmony run sync:strings` 同步，再审阅生成差异。功能或协议变更应更新对应迁移状态及本交接记录，注明验证日期和实际覆盖范围。
