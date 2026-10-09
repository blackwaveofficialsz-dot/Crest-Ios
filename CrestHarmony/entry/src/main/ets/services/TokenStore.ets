import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

// No token, password or profile data is written to preferences or logs.
export class TokenStore {
  private alias: Uint8Array;
  constructor(name: string = 'crest.refresh.v1') { this.alias = new util.TextEncoder().encodeInto(name); }
  read(): string {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.alias); query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const result = asset.querySync(query);
      if (!result.length) return '';
      return util.TextDecoder.create('utf-8').decodeToString(result[0].get(asset.Tag.SECRET) as Uint8Array);
    } catch (error) {
      if ((error as BusinessError).code === 24000002) return '';
      throw new Error('安全凭据读取失败');
    }
  }
  write(value: string): void {
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, this.alias);
    attributes.set(asset.Tag.SECRET, new util.TextEncoder().encodeInto(value));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    asset.addSync(attributes);
  }
  clear(): void {
    const query: asset.AssetMap = new Map(); query.set(asset.Tag.ALIAS, this.alias);
    try { asset.removeSync(query); } catch (error) { if ((error as BusinessError).code !== 24000002) throw error as Error; }
  }
}
