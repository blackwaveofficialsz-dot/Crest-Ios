import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
export async function copyText(text: string): Promise<void> {
  const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
  await pasteboard.getSystemPasteboard().setData(data);
}
export async function shareText(context: common.UIAbilityContext, text: string): Promise<void> {
  const data = new systemShare.SharedData({ utd: utd.UniformDataType.TEXT, content: text, title: 'Crest' });
  const controller = new systemShare.ShareController(data);
  await controller.show(context, { selectionMode: systemShare.SelectionMode.SINGLE, previewMode: systemShare.SharePreviewMode.DETAIL });
}
