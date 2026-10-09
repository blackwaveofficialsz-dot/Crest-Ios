# iOS TestFlight 发布与交接指南

本文面向接手 Crest iOS 发布的同事，覆盖首次配置、Archive、上传 App Store Connect、分发 TestFlight 和发布记录。项目配置与 Apple 要求核对日期：**2026-10-09**。后续发布前应再次确认 Apple 的 SDK 要求及账号状态。

推荐顺序：确认账号权限 → 处理本仓库发布待办 → 更新构建号 → Release 真机验收 → Archive 并上传 → 内部测试 → 按需提交外部测试审核。

## 1. 当前工程参数

以下是核对时的仓库配置，不能作为 App Store Connect 已创建应用或已有发布权限的证明。

| 项目 | 当前值／位置 |
| --- | --- |
| 工程 | [Crest.xcodeproj](../Crest.xcodeproj) |
| Target / Scheme | `Crest` / `Crest` |
| Bundle ID | `com.blackwave.crest` |
| Team ID | `RZA2NW5788`，发布前确认属于实际发行团队 |
| 签名 | `Automatic`；`CODE_SIGNING_ALLOWED`、`CODE_SIGNING_REQUIRED` 均为 `YES` |
| Version | `1.0`，对应 `MARKETING_VERSION` |
| Build | `3`，对应 `CURRENT_PROJECT_VERSION`；下次可用号码须查询 App Store Connect |
| 最低系统 | iOS / iPadOS `17.0` |
| 支持设备 | iPhone、iPad，`TARGETED_DEVICE_FAMILY = "1,2"` |
| Archive 配置 | 共享 [Crest.xcscheme](../Crest.xcodeproj/xcshareddata/xcschemes/Crest.xcscheme) 已指定 `Release` |
| 构建设置 | [project.pbxproj](../Crest.xcodeproj/project.pbxproj) |
| 默认服务地址 | `https://blackwave.org.cn/yuanji` |

自 2026 年 4 月 28 日起，上传 App Store Connect 的 iOS / iPadOS 应用须使用 **Xcode 26 或更新版本及 iOS / iPadOS 26 SDK 或更新版本**构建。SDK 要求不等于最低安装系统要求，不需要因此把项目的 iOS 17.0 部署目标改为 26。[Apple SDK 要求](https://developer.apple.com/news/upcoming-requirements/?id=04282026a)

## 2. 首次发布需要准备什么

| 材料／权限 | 准备要求 |
| --- | --- |
| Apple Developer Program | 有效的发行团队会员资格；在 Xcode 的 Settings → Accounts 登录自己的获授权 Apple 账号 |
| App Store Connect 权限 | 上传构建可使用 Account Holder、Admin、App Manager 或 Developer；还需拥有该 App 的访问权限 |
| 创建应用、管理外部测试 | 由 Account Holder、Admin 或 App Manager 操作；只有 Developer 权限的同事需由负责人完成这部分 |
| 协议 | Account Holder 检查并接受当前需要签署的协议，避免创建 App 被阻止 |
| App ID 与应用记录 | 确认团队下的显式 Bundle ID 为 `com.blackwave.crest`，且与工程和 App Store Connect 一致 |
| 签名权限 | 能访问所需证书、Identifiers 和 Profiles，或由团队管理员准备可用的分发签名；有上传权限不代表自动拥有创建证书的权限 |
| 测试与审核账号 | 可用的密码登录账号、企业工作空间和有数据的测试门店；通过安全渠道交付凭据 |
| 测试资料 | Beta App Description、Feedback Email、What to Test；外部测试另准备审核联系人及登录说明 |

账号角色以 Apple 的[上传权限](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)、[创建应用要求](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)和[外部测试要求](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)为准。不要共享个人 Apple 账号密码、双重认证验证码或把证书私钥提交到仓库。

如果 App Store Connect 已有这个 Bundle ID 对应的 Crest，沿用现有记录。若尚未创建，由有权限的同事在 **Apps → + → New App** 填写：

| 字段 | 填写说明 |
| --- | --- |
| Platforms | iOS |
| Name | 正式确认的应用名称；工程显示名当前为 `Crest`，名称可用性以后台为准 |
| Primary Language | 团队确认的主语言 |
| Bundle ID | 选择 `com.blackwave.crest`；列表中没有时先检查团队和 Identifier |
| SKU | 团队内部唯一编号，例如 `crest-ios`，仅为示例，先确认未占用 |
| User Access | 为发布和测试负责人授予该 App 的访问权限 |

同一团队内的人员交接通常只需要调整账号权限。若涉及开发者团队归属变化，先核对 App 转移、签名及 Keychain 连续性；不要仅为方便打包而随意更换 Bundle ID 或 Team。

## 3. 本仓库上传前必须核查的事项

以下是本次从文件中确认的状态，**尚未执行修复、Archive 或上传验证**。

### 3.1 隐私清单

当前 iOS 工程未发现 `PrivacyInfo.xcprivacy`。[SessionStore.swift](../Crest/Session/SessionStore.swift) 使用 `UserDefaults`，[CrestApp.swift](../Crest/App/CrestApp.swift) 和登录页也使用 `@AppStorage`。应至少核查 User Defaults 对应的 required reason API 声明，并一并检查其他 API、依赖及实际收集的数据。

发布负责人需要：

1. 在 Xcode 中为 `Crest` target 添加 App Privacy 文件 `PrivacyInfo.xcprivacy`。
2. 按实际用途填写 `NSPrivacyAccessedAPITypes` 及 Apple 允许的理由，不直接复制其他项目的理由代码。
3. 核对数据收集、关联身份与追踪声明；登录、聊天内容、头像和经营数据等均应结合客户端及后端实际处理方式判断。
4. 确认文件加入目标并包含在归档应用中；仅把文件放进源码目录不足以证明已打包。

Apple 已要求使用 required reason API 的应用在隐私清单中描述用途，否则 App Store Connect 不接受提交。操作参考：[添加隐私清单](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)、[声明 required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)。

### 3.2 加密申报及 Release 的 Info.plist

项目通过 HTTPS 通信，[AnalyticsCache.swift](../Crest/API/AnalyticsCache.swift) 还使用 CryptoKit 的 `AES.GCM` 加密本地经营分析缓存。应据此回答 App Store Connect 的加密问卷；不能仅以“使用 HTTPS”为依据判断全部加密用途。

当前工程未配置 `ITSAppUsesNonExemptEncryption`。这不自动意味着需要上传加密证明，实际是否豁免、是否需要材料，应由发布负责人根据问卷和 Apple 指引确认。如果后台显示 **Missing Compliance**，进入该构建的加密合规入口补全回答；需要材料时按后台提示提交。[Apple 加密申报说明](https://developer.apple.com/help/app-store-connect/manage-app-information/determine-and-upload-app-encryption-documentation)

特别注意：当前 Debug 显式引用 [Crest/Info.plist](../Crest/Info.plist)，而 **Release 使用自动生成的 Info.plist，未设置这个文件路径**。因此，如确认需要固化加密声明，应配置到 Release 实际使用的构建设置或 Info 中，并检查归档后的 `Crest.app/Info.plist`。不要仅修改调试 plist，也不要为消除提示直接填写 `ITSAppUsesNonExemptEncryption = NO`；只有确认不存在非豁免加密时才适用。

### 3.3 图标

当前 [AppIcon.appiconset](../Crest/Assets.xcassets/AppIcon.appiconset) 使用一张 1024 × 1024 PNG，文件检测结果为 **包含 alpha 通道**。发布前核对这张传统 App Store 图标，准备不带 alpha 通道的完整方形发行资源，并通过 Organizer 的验证确认；避免出现 `Invalid large app icon`。此处记录的是源文件状态，尚未验证编译后图标。[Apple 图标配置](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)

### 3.4 后端和登录环境

- 通用 API 与经营分析的默认地址均为 `https://blackwave.org.cn/yuanji`，测试设备和审核环境必须能正常访问，证书需有效。
- `CREST_API_BASE_URL`、`CREST_ANALYTICS_API_BASE_URL` 当前由进程环境变量读取。Xcode Run 中设置的环境变量不会自动随 TestFlight 应用一起分发；如需另一个测试服务地址，应先落实发行包实际使用的配置，再归档验证。
- Debug 经营分析使用独立的 `AnalyticsOnlineSession`；Release 使用当前登录账号和工作空间。因此 Debug 显示过分析数据，不能证明 TestFlight 的测试账号也有相应权限。
- 不要依赖 `CREST_ANALYTICS_USERNAME` / `CREST_ANALYTICS_PASSWORD` 让发行包自动登录。准备正常的测试账号，为其授予测试企业／门店权限并填充可核验的数据。
- 核对实际使用的隐私政策、用户协议及反馈入口。隐私清单、用户可读的隐私政策和 App Store Connect 的隐私信息是不同材料，应与实际数据处理保持一致。

## 4. 每次打包前的操作

1. 确定交付分支、提交号和本次变更。检查未提交及未跟踪文件，确保新增源码、资源和隐私清单都包含在交付版本中。
2. 打开 `Crest.xcodeproj`，选择 `Crest` target → **Signing & Capabilities**，确认 Team、Bundle Identifier 和 Automatically manage signing。保持签名启用，处理所有签名错误。
3. 在 **General → Identity** 核对 Version、Build。当前仓库为 `1.0 (3)`，但这不代表后台最新也是 3。查询 App Store Connect 后，为新上传包选择未使用且递增的 Build，并确认 Release 的最终值。相同 Version 下多次测试可以只递增 Build。
4. 在 **Product → Scheme → Edit Scheme → Archive** 确认 Build Configuration 为 `Release`。
5. 用 Release 配置在真机检查下面的核心流程。可以临时将 Run 的 Build Configuration 设为 Release；完成后恢复日常开发配置。不要携带调试环境变量作为发布验收前提。

| 验收项 | 预期结果 |
| --- | --- |
| 登录与会话 | 密码登录、冷启动恢复、退出及重新登录正常 |
| 工作空间 | 测试账号能进入预期企业，切换后数据和权限正确 |
| 对话 | 发消息、流式回复、历史记录及异常提示正常 |
| 经营分析 | 当前账号能加载门店数据、切换筛选并刷新；无权限／空数据有明确反馈 |
| 网络 | Wi-Fi 与蜂窝网络可访问，断网／超时后有反馈且可恢复 |
| 设备与界面 | iPhone、iPad 的关键页面，以及项目支持的横竖屏无阻塞性问题 |
| 升级 | 已有安装升级后，登录状态、历史记录和本地缓存按预期工作 |

`scripts/sync-simulator.sh` 用于模拟器构建和安装，不能生成上传 TestFlight 所需的发行归档。最终验收仍需使用从 TestFlight 安装的实际构建。

## 5. 在 Xcode 中 Archive 并上传

1. 选择 Scheme `Crest`，把运行目标切换为 **Any iOS Device (arm64)** 或当前 Xcode 对应的通用 iOS 真机目标，不选择 Simulator。
2. 执行 **Product → Archive**。完成后进入 **Window → Organizer → Archives**。
3. 选择本次 Crest 归档，核对归档时间、Version、Build 和应用标识。可通过 Show in Finder 找到 `.xcarchive`；Show Package Contents 后，应用在 `Products/Applications/Crest.app`，符号文件在 `dSYMs`。
4. 若 Organizer 提供 **Validate App**，先执行验证。处理签名、图标、隐私声明及其他校验错误后再继续；修复影响包内容的问题后要重新 Archive。
5. 选择 **Distribute App → App Store Connect → Upload**。不同 Xcode 版本可能将正常商店上传流程显示为 **TestFlight & App Store**，按当前界面选择对应项。
6. 按向导确认分发签名、描述文件及权限。若准备后续外部测试，不要选择 **TestFlight Internal Only**：这种构建只能分发给内部测试组。
7. 核对最终上传的 Version / Build。如果启用了 Xcode 自动管理版本或构建号，以上传结果为准并回写发布记录。保留归档和 dSYM，点击 Upload。
8. 出现上传成功后，进入 App Store Connect → Apps → Crest → **TestFlight** 等待处理。构建需要经 Apple 处理后才会显示并可继续配置；上传成功不等于已经可安装。
9. 若出现 Invalid Binary、Missing Compliance 或其他阻塞状态，按具体错误处理。涉及修改二进制时，更新 Build 后重新归档上传。

正常上传无需另建 `ExportOptions.plist` 或先导出 IPA；本项目按 Xcode Organizer 流程操作即可。参考：[Xcode 上传步骤](https://help.apple.com/xcode/mac/current/en.lproj/dev442d7f2ca.html)、[构建处理说明](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)、[Internal Only 限制](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)。

## 6. 分发给内部或外部测试人员

| 项目 | 内部测试 | 外部测试 |
| --- | --- | --- |
| 适用对象 | 已有 App Store Connect 权限的团队成员 | 未作为 App Store Connect 用户加入的同事、业务验收人员等 |
| 人数上限 | 100 名符合条件的内部测试员 | 每个 App 最多 10,000 名外部测试员 |
| Apple Beta 审核 | 通常可在构建处理及合规完成后开始 | 首个提交的构建需要完整审核；同版本后续构建仍以后台审核状态为准 |
| 加入方式 | 加入内部组并分配构建 | 邮件邀请或公开链接 |

TestFlight 构建可测试 **90 天**，到期需要可用的新构建。内部／外部身份由 App Store Connect 用户权限决定，不由是否为本公司同事决定。[TestFlight 概览](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

### 内部测试

1. 在 **Users and Access** 中确认测试员已接受邀请，并有该 App 的访问权限。
2. 进入 **TestFlight → Internal Testing → +**，创建内部组，例如 `Crest Internal`。
3. 给组添加已处理完成的构建和测试员；自动分发按团队实际需要选择。
4. 测试员在 iPhone / iPad 安装 Apple 的 TestFlight App，使用受邀账号接受邀请并安装 Crest。
5. 核对 TestFlight 显示的 Version / Build，重复核心流程验收，再进入外部测试。

详细权限及步骤参考：[添加内部测试员](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)。

### 外部测试

1. 先创建至少一个内部测试组，再在 **TestFlight → External Testing → +** 创建外部组。
2. 完成 Test Information：测试说明、反馈邮箱、审核联系人；需要登录的应用填写有效的审核账号和操作说明。
3. 给组添加构建，填写 What to Test，按当前状态选择 **Submit Review** 或 **Start Testing**。
4. 通过审核后，按所选通知设置自动或手动开始测试，再使用邮件邀请或公开链接邀请人员。交接给少量指定人员时可直接使用邮件邀请。
5. 若被拒绝，查看 App Review 的具体反馈。仅资料问题可按反馈补充；需要修改应用时重新打包并递增 Build。

审核资料、登录账号和所需后台功能在审核期间应持续有效。不能要求审核人员向开发者临时索取短信验证码才能完成主要流程。[外部测试步骤](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)、[测试信息](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/)、[审核访问要求](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review)

## 7. 可复用的测试与审核资料

以下为填写模板，发布负责人应按本次实际功能删改；所有“待填写”内容需替换后再提交。真实凭据只填入后台指定的审核登录字段，不写入公开测试说明或本仓库。

### Beta App Description

> Crest 是面向企业工作空间的移动应用，提供智能对话、历史会话和经营分析能力。使用前需要登录，并由管理员为账号配置相应企业和门店权限。本次为测试版本，请使用团队提供的测试账号和测试数据。

### What to Test

> 本次版本：待填写 Version / Build。
>
> 本次变更：待填写实际新增或修复内容。
>
> 请重点验证：密码登录及重新打开后的会话恢复；企业工作空间切换；发送消息、流式回复及历史查看；经营分析数据加载、门店筛选和刷新；网络异常后的提示与恢复。
>
> 已知问题：待填写；如无已知问题，明确填写“无已知阻塞问题”。
>
> 反馈时请附设备型号、系统版本、构建号、操作步骤和截图，避免包含业务敏感信息。

### 外部测试审核备注

| 字段 | 待填写内容 |
| --- | --- |
| Feedback Email | 实际有人接收和处理反馈的邮箱 |
| 审核联系人 | 真实姓名、邮箱、联系电话 |
| Sign-in required | 按实际情况填写；Crest 主要业务需要登录 |
| 审核账号和密码 | 单独填写到后台指定字段，并在同一发行构建上确认可登录 |
| 测试工作空间／门店 | 审核账号已有权限的工作空间名、门店名，以及数据日期范围 |
| 操作步骤 | 密码登录 → 进入指定工作空间 → 验证对话 → 打开经营分析并选择有数据的门店／日期；以实际界面为准 |
| 特殊说明 | 网络限制、特殊操作或尚未开放的功能；未开放功能不要写成已可用 |

## 8. 常见问题

| 现象 | 排查与处理 |
| --- | --- |
| Archive 不可用／拿到模拟器包 | 确认 Scheme 为 Crest、目标为通用 iOS 真机、Archive 为 Release；模拟器产物不能直接上传 |
| 找不到匹配的 profile／签名失败 | 检查登录账号、Team、Bundle ID、证书权限及自动签名状态，不要关闭签名绕过 |
| Bundle ID 或团队不匹配 | 确认工程、开发者后台 Identifier 和 App Store Connect 记录属于同一发行团队 |
| Build 重复或版本不合法 | 查询后台最新构建，递增 Build 并重新归档，不要反复提交同一包 |
| Invalid large app icon | 核查发行图标是否含 alpha／透明内容，替换合规资源后重新归档；当前源图含 alpha |
| Missing Compliance | 结合 HTTPS 和本地 AES.GCM 用途完成问卷；需要时补材料，并检查最终 Release plist 的声明 |
| 隐私清单缺失或理由无效 | 检查 PrivacyInfo.xcprivacy 的 target 归属、打包结果及实际 API 用途；按 Apple 错误定位，不填写虚假理由 |
| 上传成功但还看不到构建 | 检查后台处理状态和处理结果邮件，并确认所选 App、平台、Version；处理失败时按错误修复 |
| Debug 正常，TestFlight 登录或分析失败 | 优先核对发行包服务地址、测试账号工作空间／门店权限，以及是否误依赖 Run 环境变量或 Debug 专用会话 |
| 外部组无法选择构建 | 检查是否误上传为 Internal Only、处理及合规是否完成、是否有权限，以及审核状态 |
| 已批准但测试员收不到新版本 | 检查构建是否已分配到组、是否已手动开始测试、邀请账号是否正确，以及设备／系统和有效期 |
| 构建过期 | 上传并分发新构建；不要把已过期的 TestFlight 版本作为长期交付方式 |

## 9. 发布完成与交接记录

以测试员通过 TestFlight 安装并验证成功作为本次分发完成标准。每次发布记录以下信息，可直接复制到团队发布记录或交接单：

| 项目 | 记录内容 |
| --- | --- |
| 发布日期／操作人 | 待填写 |
| 分支／提交号 | 待填写；标明是否含未提交变更 |
| Version / Build | 待填写 App Store Connect 最终号码 |
| Xcode / SDK | 待填写实际构建版本 |
| App / Team / Bundle ID | 待填写后台 App 记录与实际签名团队；Bundle ID 当前为 `com.blackwave.crest` |
| 服务环境 | 待填写实际默认地址、测试企业及门店；不记录密码或令牌 |
| 归档与符号文件 | `.xcarchive`、dSYM 的受控存储位置，便于后续崩溃定位 |
| 测试分发 | 内部／外部组名、审核状态、开始日期及到期时间 |
| 验收结果 | 安装人、设备／系统、通过项目及失败复现步骤 |
| 已知问题／下一负责人 | 待填写问题、处理优先级及接手人 |

交接前逐项确认：

- [ ] 新发布人能访问正确团队、应用记录及所需签名资源。
- [ ] 隐私清单、加密申报、发行图标已处理，并检查了最终归档产物。
- [ ] 从 TestFlight 安装的 Version / Build 与发布记录一致，核心流程通过。
- [ ] 外部测试所需账号、资料与审核状态已确认；仅内部测试时标注“不适用”。
- [ ] 归档、dSYM、源码提交和已知问题均有记录，测试账号通过安全渠道交接。
- [ ] 记录构建有效期，并安排在到期前交付后续版本。

如构建出现阻塞问题，先在 TestFlight 中停止该构建的测试，再修复并发布新 Build。已分发的二进制不能原地替换，停止测试也不会自动让所有设备回退到旧版本。[停止测试构建](https://developer.apple.com/help/app-store-connect/test-a-beta-version/stop-testing-a-build/)
