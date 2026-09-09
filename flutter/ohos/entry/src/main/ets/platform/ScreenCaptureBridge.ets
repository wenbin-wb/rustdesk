import { media } from '@kit.MediaKit';
import { common } from '@kit.AbilityKit';

export class ScreenCaptureBridge {
  private screenCapture: media.AVScreenCapture | null = null;
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
      this.screenCapture = await media.createAVScreenCapture();
      const config: media.AVScreenCaptureConfig = {
        videoConfig: {
          videoSourceType: media.VideoSourceType.VIDEO_SOURCE_SURFACE_YUV,
          videoCodec: media.CodecMimeType.VIDEO_AVC,
          width: width,
          height: height
        },
        audioConfig: {
          audioSourceType: media.AudioSourceType.AUDIO_MIC,
          audioCodec: media.CodecMimeType.AUDIO_AAC
        }
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
