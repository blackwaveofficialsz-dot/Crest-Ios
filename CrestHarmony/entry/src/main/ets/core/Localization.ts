import { IOS_ENGLISH } from './IOSStrings';

// Platform-specific accessibility labels and existing Harmony wording. Shared labels always use iOS first.
const HARMONY_ENGLISH: Record<string, string> = {
  '缩小': 'Zoom out', '放大': 'Zoom in',
  '正在退出登录': 'Signing out', '退出未完成': 'Sign-out incomplete',
  '登录凭据清理失败，已阻止自动登录，请重试': 'Could not remove credentials. Automatic sign-in is blocked. Try again.',
  '退出状态未能保存，请勿关闭应用，重试清理登录凭据': 'Sign-out could not be saved. Keep the app open and retry removing credentials.',
  '安全退出状态不可用，请重试': 'Sign-out storage is unavailable. Try again.',
  '请先重试清理登录凭据': 'Retry removing sign-in credentials first.',
  '登录或工作空间已变更，请重试': 'Account or workspace changed. Try again.',
  ' / 小时': ' / hour', ' 小时': ' hours', '1 至 30 个字符': '1–30 characters', '6 位验证码': '6-digit code',
  'Crest · 餐饮经营助手': 'Crest · Restaurant business assistant',
  'Crest 也可能会犯错，请核查重要信息': 'Crest can make mistakes. Check important information.',
  '上传中…': 'Uploading…', '上期无可比数据': 'No comparable previous data', '产品排行': 'Product ranking',
  '产品详情': 'Product details', '产品趋势：': 'Product trend: ', '代码已复制': 'Code copied',
  '企业工作空间专属': 'Business workspace only', '使用头像': 'Use photo', '保存中…': 'Saving…',
  '保存密码': 'Save password', '保存昵称': 'Save name', '停止回复': 'Stop response', '关闭': 'Close',
  '删除对话': 'Delete conversation', '刷新最近对话': 'Refresh recent conversations', '向 Crest 提问': 'Ask Crest',
  '回到最新': 'Jump to latest', '复制失败': 'Could not copy', '头像已更新': 'Profile photo updated',
  '头像缩放': 'Photo zoom', '实收金额': 'Net revenue', '实际人效': 'Actual revenue per hour',
  '密码已更新': 'Password updated', '导出 CSV': 'Export CSV', '展开图表': 'Expand chart', '趋势图': 'Trend chart',
  '已停止回复': 'Response stopped', '已导出 CSV': 'CSV exported', '开始一段新的对话吧': 'Start a new conversation',
  '开始日期不能晚于结束日期，结束日期不能晚于昨日': 'Start date must not follow end date. End date must be yesterday or earlier.',
  '当前日期和门店范围内没有报警记录': 'No alerts for the selected dates and stores', '忘记密码？': 'Forgot password?',
  '拖动和双指缩放，调整头像位置': 'Drag and pinch to position your photo', '搜索对话': 'Search conversations',
  '搜索对话标题': 'Search conversation titles', '新密码需为 7 至 16 位': 'New password must be 7–16 characters',
  '新密码（7 至 16 位）': 'New password (7–16 characters)', '新密码（7–16 位）': 'New password (7–16 characters)',
  '无法恢复登录': 'Could not restore session', '无法打开链接': 'Could not open link', '无法读取这张图片': 'Could not read photo',
  '日期与门店': 'Dates and stores', '昵称已更新': 'Name updated', '暂无产品数据': 'No product data',
  '暂无人效数据': 'No labor data', '暂无历史记录': 'No conversations yet', '暂无趋势数据': 'No trend data',
  '未能打开分享面板': 'Could not open sharing', '正在加载历史记录': 'Loading conversations', '正在加载对话': 'Loading conversation',
  '正在加载趋势': 'Loading trend', '正在回复': 'Responding', '正在恢复登录状态': 'Restoring session',
  '没有找到相关对话': 'No matching conversations', '渠道分布': 'Channels', '热门产品': 'Top products',
  '确认新密码': 'Confirm new password', '经营分析加载失败': 'Could not load business analytics',
  '经营总览': 'Business overview', '经营概览': 'Business overview', '继续': 'Continue',
  '缺失日期保留断点，不补零': 'Missing dates are shown as gaps, not zero', '至': 'to', '营收趋势：': 'Revenue trend: ',
  '裁剪头像': 'Crop photo', '订单分析': 'Order analysis', '订单解析': 'Order analysis', '让经营，更清晰。': 'Clarity for your business.',
  '试试其他对话标题': 'Try another conversation title', '请加入团队或切换企业工作空间': 'Join a team or switch to a business workspace',
  '请输入 6 位验证码': 'Enter a 6-digit code', '请输入昵称': 'Enter your name', '请输入有效的 11 位手机号': 'Enter a valid 11-digit phone number',
  '账号': 'Account', '趋势加载失败': 'Could not load trend', '近 30 天营收趋势': 'Revenue · last 30 days',
  '近 30 天订单趋势': 'Orders · last 30 days', '返回设置': 'Back to settings', '部分数据未加载': 'Some data could not be loaded',
  '重新生成回复': 'Regenerate response', '重置凭据已失效，请重新验证': 'Reset credential expired. Verify again.',
  '重试': 'Retry', '门店表现': 'Stores', '验证并继续': 'Verify and continue',
  '显示 %@ / %@ 行': 'Showing %@ / %@ rows', '展开 %@ 行': 'Show %@ rows',
  '结果不完整': 'Partial result', '数据暂不可用': 'Data unavailable', '结果状态未知': 'Unknown result status',
  '请求失败': 'Request failed', '网络连接失败，请稍后重试': 'Connection failed. Try again later.',
  '昵称需为 1 至 30 个字符': 'Name must be 1–30 characters', '密码需为 7 至 16 位': 'Password must be 7–16 characters',
  '请输入当前密码': 'Enter your current password', '请输入邀请码': 'Enter an invitation code',
  '操作未完成': 'Operation could not be completed', '两次输入的密码不一致': 'Passwords do not match',
  '操作频繁，请稍等 %lld 秒后再试。': 'Too many requests. Try again in %lld seconds.',
  '%@ 秒后重新发送': 'Resend in %@ seconds', '较上期 %@': '%@ vs. previous period',
  '%@ 单': '%@ orders', '数据状态：%@': 'Data status: %@', '近 30 天 · %@': 'Last 30 days · %@',
  '销量 %@ · 金额占比 %@%%': 'Quantity %@ · Sales share %@%%', '展示前 %@ 项，共 %@ 项': 'Showing %@ of %@ items',
  '业务日期：%@': 'Business date: %@', '实际 %@ · 基线 %@': 'Actual %@ · Baseline %@',
  '偏差 %@%% · %@': 'Deviation %@%% · %@', '%@ 家门店': '%@ stores',
  '正在连接': 'Connecting', '正在处理': 'Processing', '正在查询数据': 'Querying data'
};

export function resolvedLocale(language: string, system: string): string {
  return (language === 'system' ? system : language).toLowerCase().startsWith('zh') ? 'zh-Hans' : 'en';
}
// UI labels only: never translate backend response text, identifiers, account names or prompts in transit.
export function translate(key: string, locale: string): string {
  return locale === 'en' ? IOS_ENGLISH[key] || HARMONY_ENGLISH[key] || key : key;
}
export function localizedFormat(key: string, locale: string, args: string[]): string {
  let index = 0;
  return translate(key, locale).replace(/%%|%@|%lld|%ld|%d|%s/g, (token: string) => token === '%%' ? '%' : (args[index++] ?? token));
}
