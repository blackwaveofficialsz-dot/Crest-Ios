import Foundation

// 不启动 App，也不修改默认开关；直接验证同一份展示状态逻辑。
@main
struct ChatPlaybackChecks {
    static func main() {
        precondition(!ChatFeatureFlags.lightweightTypewriter, "功能必须保持默认关闭")
        let source = String(repeating: "你好 👨‍👩‍👧‍👦 café！", count: 30)
        var playback = ChatTextPlayback(messageID: "reply-1")
        playback.receive(source, animated: true)
        precondition(playback.visibleText.isEmpty && playback.hasPendingText)
        playback.resume(at: 10)
        playback.advance(at: 10)
        precondition(playback.visibleText.isEmpty, "时间未推进时不能消耗正文")
        playback.advance(at: 10.032)
        precondition(!playback.visibleText.isEmpty && playback.hasPendingText)
        precondition(source.hasPrefix(playback.visibleText), "只能展示真实正文前缀")

        let prefix = playback.visibleText
        let nextSource = source + "继续收到的真实 SSE 内容"
        playback.receive(nextSource, animated: true)
        precondition(playback.visibleText == prefix, "网络增量不能重置展示进度")
        playback.advance(at: 10.064)
        precondition(nextSource.hasPrefix(playback.visibleText))
        playback.finish(at: 10.064)
        playback.advance(at: 10.6641)
        precondition(playback.visibleText == nextSource && !playback.hasPendingText,
                     "成功后最多保留 600ms 展示尾巴")

        playback = ChatTextPlayback(messageID: "reply-2")
        playback.receive(source, animated: true)
        playback.revealAll()
        precondition(playback.visibleText == source && !playback.hasPendingText)
        playback.receive(nextSource, animated: true)
        precondition(playback.visibleText == nextSource && !playback.hasPendingText,
                     "停止动画后的同条回复不能重启动画")

        for text in ["# 标题\n\n正文", source] {
            playback = ChatTextPlayback(messageID: "accessibility")
            playback.receive(text, animated: false)
            precondition(playback.visibleText == text && !playback.hasPendingText)
            playback.receive(text + "后续", animated: true)
            precondition(playback.visibleText == text + "后续",
                         "后台/减少动态效果后的回复保持直接展示")
        }

        for text in ["```swift\nlet x = 1\n```", "~~~\n代码\n~~~",
                     "| 项目 | 金额 |\n| --- | --- |\n| 收入 | 100 |",
                     String(repeating: "长", count: 20_001)] {
            playback = ChatTextPlayback(messageID: "complex")
            playback.receive(text, animated: true)
            precondition(playback.visibleText == text && !playback.hasPendingText,
                         "复杂 Markdown / 超长回复直接渲染")
        }

        let unicode = "👨‍👩‍👧‍👦🇨🇳👍🏽e\u{301}中文"
        playback = ChatTextPlayback(messageID: "unicode")
        playback.receive(unicode, animated: true)
        playback.resume(at: 0)
        var time = 0.0
        while playback.hasPendingText {
            time += 0.032
            playback.advance(at: time)
            precondition(unicode.hasPrefix(playback.visibleText))
            precondition(playback.visibleText == String(unicode.prefix(playback.visibleText.count)),
                         "不可拆开 emoji 或组合字符")
        }
        precondition(playback.visibleText == unicode)

        playback = ChatTextPlayback(messageID: "replacement")
        playback.receive(source, animated: true)
        playback.receive("服务器修正后的全文", animated: true)
        precondition(playback.visibleText == "服务器修正后的全文" && !playback.hasPendingText)
        playback = ChatTextPlayback(messageID: "new-turn")
        playback.receive("下一条回复", animated: true)
        precondition(playback.visibleText.isEmpty && playback.hasPendingText,
                     "新回复有独立进度，不复用上条的直接展示状态")

        // 用真实渲染器验证：分片正文经过打字机后完整交还 Markdown 缓存。
        let markdown = "# 经营摘要\n\n本月经营正常。\n\n- 收入增长\n- 成本稳定"
        var cache = MarkdownBlockCache(content: "", isStreaming: true)
        var received = ""
        playback = ChatTextPlayback(messageID: "markdown")
        time = 0
        playback.resume(at: time)
        for character in markdown {
            received.append(character)
            playback.receive(received, animated: true)
            time += 0.032
            playback.advance(at: time)
            cache.update(content: playback.visibleText, isStreaming: true)
        }
        playback.finish(at: time)
        playback.advance(at: time + 0.601)
        cache.update(content: playback.visibleText, isStreaming: false)
        precondition(playback.visibleText == markdown)
        precondition(cache.blocks.count == 3)
        guard case .heading(level: 1, text: "经营摘要") = cache.blocks[0],
              case .unorderedList(let items) = cache.blocks[2], items.count == 2 else {
            fatalError("最终 Markdown 结构必须保持完整")
        }

        print("PASS: 默认关闭、增量接收、平滑展示、600ms 收尾、生命周期降级、Unicode、复杂内容旁路、新会话隔离、Markdown 集成")
    }
}
