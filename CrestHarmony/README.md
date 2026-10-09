# Crest HarmonyOS 原生客户端

使用 ArkTS / ArkUI Stage 模型实现，面向 HarmonyOS NEXT 5.0（API 12）及以上。不是 Android APK 兼容版，不使用 WebView 包装页面。

**当前状态：主要页面和接口已实现，官方鸿蒙 SDK 原生编译通过，129 项离线测试通过；HarmonyOS 7.0.0 模拟器已完成登录会话、昵称、侧栏、裁剪预览／取消、历史与回复抽样检查，最新首页浅色样式已对照，最终 HAP 已安装。仍不是可发布版本。** 用户确认头像变化为人工操作，保留当前头像，不恢复旧图；受控上传回读、实时流式与完整聊天状态、分析、最低系统及真机仍待验收，详见 `MIGRATION_STATUS.md`。已使用 DevEco Studio 26.0.0.851 和随附 SDK 26.0.0.105 生成未签名 debug HAP。最低／目标 API 配置仍为 12，不能据此替代 API 12 设备兼容性测试。

## 工程位置与配置

- `../Crest`：功能、流程、文案和视觉的同步标准，以当前磁盘中的 iOS 源码为准。
- `../CrestAndroid`：Android 同步辅助参考，不能覆盖 iOS 的业务行为。
- 本目录：独立鸿蒙项目，不改变其他两端源码或后端协议。
- Bundle name：`com.blackwave.crest`，申请发布标识后需确认是否保持该值。
- 后端：`entry/src/main/ets/services/Api.ets` 中的 `https://blackwave.org.cn/yuanji`，与参考端一致。
- 权限：仅声明网络权限；头像选择和 CSV 保存均由用户点击后打开系统选择器。
- 无运行时第三方依赖；npm 中的 TypeScript 仅用于开发测试，不进入 HAP。

## 在 DevEco Studio 打开

1. 从 [华为官方 DevEco Studio 下载页](https://developer.huawei.com/consumer/cn/deveco-studio/resources/)安装 IDE 和随附 HarmonyOS SDK。本项目已在 26.0.0.851 上通过原生构建。
2. 打开本目录，等待工程同步和 Hvigor 依赖解析。不要作为 Android 工程导入。
3. 在 IDE 的签名设置中为 `com.blackwave.crest` 配置开发签名；账号、密码、证书和私钥不要写入仓库。
4. 选择 HarmonyOS NEXT 模拟器或真机，构建 `entry` 并运行，再执行下文设备验收。

`compileSdkVersion` 显式配置为 `26.0.0`，使用 DevEco 随附 SDK；`compatibleSdkVersion` 和 `targetSdkVersion` 保持 `5.0.0(12)`。不为消除检查错误而抬高最低版本，新增 API 必须核对版本和设备行为。

配置好官方命令行工具后，也可指定其入口执行：

```sh
export CREST_HVIGORW=/absolute/path/to/official/hvigorw
npm run build:hap
```

`build:hap` 自动识别 macOS 标准位置 `/Applications/DevEco-Studio.app`，也支持上述自定义入口。工具链缺失时明确失败，不生成伪造 HAP。产物位于 `entry/build/default/outputs/default/entry-default-unsigned.hap`；项目未包含发行签名文件。命令行环境设置见[华为官方构建文档](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V14/ide-command-line-building-app-V14)。

## 本地验证

```sh
npm ci
npm run sync:strings
npm test
npm run check:project
npm run build:hap
```

- `sync:strings`：只读取 iOS 的 `Localizable.xcstrings`，生成鸿蒙端的 417 条英文翻译。运行测试时会核对目录是否与 iOS 一致，不修改 iOS 资源。
- `test`：129 项离线测试，覆盖 SSE 拆包／去重／续传请求、AGUI 过滤与格式化、流式 Markdown 缓存、头像裁剪、经营日期／明细／CSV、登录刷新、跨工作空间并发状态及语言／图标资源一致性；另验证真实 Api 源码的 PATCH、空响应、401、解析／网络失败和资源释放，以及登录背景逐帧重置、后台／卸载停止绘制、四步认证按钮状态和矢量图标单位。包括安全存储故障、迟到结果、空间记忆、昵称和侧栏，以及第二批 EXIF、512 像素输出、编码上限、选图不自动保存、重复提交、安全区、逐层返回、原生 Sheet 回调及状态栏异步恢复测试。第三批新增回复显隐条件、复制分享原文与平台桥接、反馈时限／迟到结果、表格计数及标题响应绑定；第四批新增验证码恢复、减弱动画和思考波形时序测试；不替代 ArkUI 设备渲染验收。
- 状态测试执行转换后的真实 Session / ChatStore 源码；只在测试中替换鸿蒙系统桥接和网络。不连接生产账户、不发送短信、不写入业务数据。
- `check:project`：检查路径、配置、页面入口、权限、字体许可、服务语法和原生 UI 限制。**不会验证 ArkUI DSL、SDK 类型、签名或设备行为。**
- `build:hap`：2026-10-08 原生构建通过，产出未签名 debug HAP；尚不等于生产接口端到端或发行验收通过。
- 模拟器：CrestPhone（HarmonyOS 7.0.0 / API 26、ARM64、4 GB RAM）安装／启动成功，已取得登录页截图。首次运行发现全分辨率模糊背景导致渲染内存压力；改为半宽半高画布、等比例放大并逐帧重置后，约 45 秒连续采样未再复现系统低内存结束，渲染进程 RSS 约 77–100 MiB。长时间、真机及其他页面性能仍需验证。

- 第一批设备冒烟检查：输入法基本模式、真实登录／退出／重启、空间记忆、昵称保存／回读／恢复、照片选择器取消、侧栏拖动、资料页深浅色与键盘避让通过。第二批完成全屏裁剪 EXIF 6 预览、滑条缩放／单指平移／取消、安全区、状态栏恢复和资料返回设置，以及深浅色历史菜单／确认框打开取消、重命名键盘避让；本次未提交头像或历史写操作。菜单模糊、浅色弹窗材质仍有差异；完整聊天／AGUI、双指缩放和上传回读、异常网络与同模式 iOS 全量对照仍待验收。

## 源码结构

| 目录 | 职责 |
| --- | --- |
| `core` | 数据模型、SSE／AGUI 协议、Markdown 与流式缓存、数据格式、经营日期／明细／CSV、多语言 |
| `services` | HTTP／流式网络、登录与安全凭据、主题／语言设置、系统分享和文件导出 |
| `state/ChatStore.ets` | 会话、历史记录、流式回复、确认／取消和并发防护 |
| `components` | 原生动效背景、图标／玻璃样式、头像编辑、富文本、表格和趋势图 |
| `pages` | 登录、主界面、设置及经营分析 |

## 重要安全约束

Refresh token 通过 Asset Store 保存，并关闭跨设备同步；access token 仅放内存。安全存储失败时不降级为明文；退出先清空私有状态并保存非敏感阻止恢复标记，安全删除失败显示重试且不允许新登录。登录表单内容不持久化；没有业务请求日志。没有内置账号、密码、支付 SDK 或应用内购买。工作空间偏好按用户分别保存，不替代服务端授权检查。

应用图标已复用 iOS 的原始 PNG，两处鸿蒙图标资源均有字节一致性测试；移除了原先两个临时 SVG。正式隐私政策／用户协议地址、鸿蒙应用标识和发布签名仍需发布方确认。Rubik 字体沿用 Android 中的 OFL 授权资源，中文使用系统字体，未复制 Apple 专有字体。

完整范围及未完成项见 [MIGRATION_STATUS.md](MIGRATION_STATUS.md)。
