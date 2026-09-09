import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

export class FilePickerBridge {
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  public async pickFiles(): Promise<string[]> {
    try {
      const documentViewPicker = new picker.DocumentViewPicker(this.context);
      const documentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.maxSelectNumber = 10;
      const uris = await documentViewPicker.select(documentSelectOptions);
      return uris ?? [];
    } catch {
      return [];
    }
  }

  public async saveFile(defaultFileName: string): Promise<string> {
    try {
      const documentViewPicker = new picker.DocumentViewPicker(this.context);
      const documentSaveOptions = new picker.DocumentSaveOptions();
      documentSaveOptions.newFileNames = [defaultFileName];
      const uris = await documentViewPicker.save(documentSaveOptions);
      if (uris && uris.length > 0) {
        return uris[0];
      }
    } catch {
      return '';
    }
    return '';
  }
}
