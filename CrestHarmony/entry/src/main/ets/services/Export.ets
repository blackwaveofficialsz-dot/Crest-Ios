import { common } from '@kit.AbilityKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { csv } from '../core/Analytics';

// Only the URI explicitly selected by the user is written. No blanket file permission.
export async function exportCSV(context: common.UIAbilityContext, name: string, rows: string[][]): Promise<boolean> {
  const dialog = new picker.DocumentViewPicker(context);
  const destinations = await dialog.save({ newFileNames: [name + '.csv'], fileSuffixChoices: ['CSV|.csv'] });
  if (!destinations.length) return false;
  const bytes = new util.TextEncoder().encodeInto(csv(rows));
  const file = await fs.open(destinations[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
  try {
    let written = 0;
    while (written < bytes.length) {
      const count = await fs.write(file.fd, bytes.buffer.slice(written));
      if (count <= 0) throw new Error('Export write incomplete');
      written += count;
    }
  } finally { await fs.close(file); }
  return true;
}
