import SwiftUI

/// 聊天页面随主题切换的低对比度背景。
struct ChatBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: true) { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(AppColors.background)
            )

            var ribbon = Path()
            ribbon.move(to: CGPoint(x: -size.width * 0.3, y: size.height * 0.02))
            ribbon.addCurve(
                to: CGPoint(x: size.width * 1.28, y: size.height * 0.46),
                control1: CGPoint(x: size.width * 0.18, y: size.height * 0.38),
                control2: CGPoint(x: size.width * 0.78, y: -size.height * 0.12)
            )

            context.drawLayer { glow in
                glow.opacity = colorScheme == .dark ? 0.15 : 0.07
                glow.addFilter(.blur(radius: min(size.width, size.height) * 0.12))
                glow.stroke(
                    ribbon,
                    with: .linearGradient(
                        Gradient(
                            colors: colorScheme == .dark
                                ? [.clear, .white, .clear]
                                : [.clear, .black, .clear]
                        ),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: size.height * 0.5)
                    ),
                    style: StrokeStyle(
                        lineWidth: min(size.width, size.height) * 0.28,
                        lineCap: .round
                    )
                )
            }

            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(
                        colors: [.clear, AppColors.background.opacity(0.34), AppColors.background]
                    ),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
