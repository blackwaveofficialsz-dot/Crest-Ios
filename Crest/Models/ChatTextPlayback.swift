import Foundation

enum ChatFeatureFlags {
    // 仅准备代码；Debug / Release 均不启用，待接口联调后再显式切换。
    static let lightweightTypewriter = false
}

/// 只控制展示进度；消息原文仍由 ChatView 的 messages 保存。
struct ChatTextPlayback {
    let messageID: String?
    private(set) var visibleText = ""
    private var receivedText = ""
    private var characters: [Character] = []
    private var visibleCount = 0
    private var bypassAnimation = false
    private var lastTick: TimeInterval = 0
    private var finishDeadline: TimeInterval?

    init(messageID: String? = nil) {
        self.messageID = messageID
    }

    var hasPendingText: Bool { visibleCount < characters.count }

    mutating func receive(_ text: String, animated: Bool) {
        let isAppend = text.hasPrefix(receivedText)
        receivedText = text
        // 复杂 Markdown 与长回复直接交给现有块渲染器，避免反复重排。
        guard animated, !bypassAnimation, isAppend, text.utf16.count <= 20_000,
              !text.contains("```"), !text.contains("~~~"), !text.contains("|") else {
            revealAll()
            return
        }
        characters = Array(text)
        visibleCount = min(visibleCount, characters.count)
        visibleText = String(characters.prefix(visibleCount))
    }

    mutating func resume(at time: TimeInterval) {
        lastTick = time
    }

    mutating func advance(at time: TimeInterval) {
        guard hasPendingText else { return }
        if let finishDeadline, time >= finishDeadline {
            revealAll()
            return
        }
        let elapsed = max(0, time - lastTick)
        guard elapsed >= 0.016 else { return }
        lastTick = time
        let remaining = characters.count - visibleCount
        let catchUpDuration = finishDeadline.map { max(0.032, $0 - time) } ?? 0.75
        let speed = max(80, Double(remaining) / catchUpDuration)
        let step = min(remaining, max(1, Int(ceil(speed * min(elapsed, 0.1)))))
        visibleText.append(contentsOf: characters[visibleCount..<(visibleCount + step)])
        visibleCount += step
    }

    mutating func finish(at time: TimeInterval) {
        finishDeadline = time + 0.6
    }

    /// 失败、减少动态效果或退入后台后，本条回复不再重启动画。
    mutating func revealAll() {
        visibleText = receivedText
        characters.removeAll()
        visibleCount = 0
        bypassAnimation = true
        finishDeadline = nil
    }
}
