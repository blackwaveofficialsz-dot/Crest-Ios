import SwiftUI

extension View {
    /// iOS 26 使用原生玻璃按钮，旧系统回退到原生描边圆形按钮。
    @ViewBuilder
    func systemGlassCircleButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
                .buttonBorderShape(.circle)
        } else {
            buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .tint(AppColors.primaryText)
        }
    }

    /// 保留强调色填充的系统玻璃圆形按钮。
    @ViewBuilder
    func systemGlassProminentCircleButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
        } else {
            buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
        }
    }
}
