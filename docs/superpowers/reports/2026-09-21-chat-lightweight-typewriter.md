# Crest 真实流式接收 + 轻量打字机（暂不启用）

## 状态与范围

- 原生 iOS / SwiftUI 项目：Crest。
- `Crest/Models/ChatTextPlayback.swift` 中 `ChatFeatureFlags.lightweightTypewriter = false`，Debug 和 Release 均关闭。没有用户设置入口或运行时覆盖。
- 未安装到模拟器/真机，未启动新版本，未发布。
- 未修改接口协议：继续复用 `POST /api/v1/chat` 的真实 SSE，以及现有约 50ms 的网络事件合批。**不代表已经接入新 AG-UI 协议。**

## 已准备的能力

1. 原始正文继续保存在消息数据中，独立的 `ChatTextPlayback` 只控制可见前缀。历史消息直接显示全文，不重新播放。
2. 启用后约每 32ms 推进一次展示，根据待显示字符量加速；正常接收完成后，剩余正文约 600ms 内展示完毕。网络结束与展示结束分别管理，动画不阻塞下一条提问。
3. 使用 Swift `Character`，不截断已收到文本中的 emoji 和组合字符。
4. 保留现有 Markdown 块缓存渲染。代码围栏、含竖线的内容（保守覆盖表格）、超过 20,000 个 UTF-16 单元的正文直接显示，不增加打字机延迟。
5. 不提供“立即显示”按钮，由轻量打字机自动追赶并快速收尾。复制和分享继续使用消息原文。
6. 用户向上翻阅时停止自动跟随。右下角圆形悬浮按钮在真实请求进行中显示三个点的原生循环呼吸动画，即使正在跟随底部也保持可见；点击仍滚动到最底部并恢复跟随，不会中止回复。请求完成或失败后停止三点动画：未恢复跟随时变为向下箭头，正在跟随时隐藏。复用项目原生圆形按钮样式，保留 44pt 点击区域、“滚动到最底部”的无障碍名称及“正在生成回复”的状态值。减少动态效果、VoiceOver、后台或覆盖聊天的界面打开时停用动画，生成状态保留静态三点；未新增计时器。开关关闭时不启用新增滚动手势、按钮及动画。
7. 失败、取消、离开页面清理展示任务；切换会话/工作区重置播放状态。旧请求不能继续修改新一轮的消息状态。
8. 按 UI/UX 技能的无障碍与生命周期要求，使用原生按钮和至少 44pt 点击区域；减少动态效果、VoiceOver、退入后台或切走聊天区域时直接显示已收到正文，并停止打字机任务。

## 验证

- 独立回归脚本：`scripts/check-chat-playback.swift`。直接测试应用使用的展示逻辑，不改变功能开关，不启动 App。
- 覆盖默认关闭、增量接收与前缀一致性、结束收尾、停止动画后的增量、Unicode、复杂 Markdown/长文本旁路、正文替换、新消息隔离，以及与真实 Markdown 缓存的集成。
- iOS Simulator Debug / Release 编译均通过；未执行安装或启动。构建保留项目要求的签名配置。`git diff --check` 通过。
- 尚未做启用状态下的真机 UI、滚动手势、后台切换及实际后端端到端测试；状态逻辑检查不替代这些验收。

可重复的独立检查：

```sh
swiftc -module-cache-path /private/tmp/crest-playback-module-cache \
  Crest/Models/ChatTextPlayback.swift \
  Crest/Components/Chat/MarkdownBlockParser.swift \
  scripts/check-chat-playback.swift \
  -o /private/tmp/crest-chat-playback-check
/private/tmp/crest-chat-playback-check
```

## 后续启用前

待明确接口同步范围后，再适配/验证相应的流式事件协议，并在获得启用确认后修改唯一开关。在联调环境验收长回复、代码/表格、断流、重试、切换租户/历史会话、前后台、VoiceOver、上翻阅读以及复制全文；通过后再安排安装与发布。本次不做上述切换。
