import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';

export class ScreenCaptureBridge {
  private screenCapture: media.AVScreenCaptureRecorder | null = null;
  private isCapturing: boolean = false;
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  public async startCapture(width: number = 1920, height: number = 1080): Promise<boolean> {
    if (this.isCapturing) {
      return true;
    }
    try {
      this.screenCapture = await media.createAVScreenCaptureRecorder();
      const config: media.AVScreenCaptureRecordConfig = {
        fd: 0,
        frameWidth: width,
        frameHeight: height,
        videoBitrate: 6000000
      };
      await this.screenCapture.init(config);
      await this.screenCapture.startRecording();
      this.isCapturing = true;
      return true;
    } catch {
      this.isCapturing = false;
      return false;
    }
  }

  public async stopCapture(): Promise<boolean> {
    if (!this.isCapturing || !this.screenCapture) {
      return true;
    }
    try {
      await this.screenCapture.stopRecording();
      await this.screenCapture.release();
      this.screenCapture = null;
      this.isCapturing = false;
      return true;
    } catch {
      return false;
    }
  }

  public isRunning(): boolean {
    return this.isCapturing;
  }
}
