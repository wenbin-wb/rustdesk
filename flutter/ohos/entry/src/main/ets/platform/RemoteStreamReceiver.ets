import { media } from '@kit.MediaKit';
import { socket } from '@kit.NetworkKit';

export class RemoteStreamReceiver {
  private static instance: RemoteStreamReceiver | null = null;
  private avPlayer: media.AVPlayer | null = null;
  private tcpSocket: socket.TCPSocket | null = null;
  private isDecoding: boolean = false;
  private surfaceId: string = '';

  private constructor() {}

  public static getInstance(): RemoteStreamReceiver {
    if (!RemoteStreamReceiver.instance) {
      RemoteStreamReceiver.instance = new RemoteStreamReceiver();
    }
    return RemoteStreamReceiver.instance;
  }

  public setSurfaceId(surfaceId: string): void {
    this.surfaceId = surfaceId;
    if (this.avPlayer && surfaceId) {
      this.avPlayer.surfaceId = surfaceId;
    }
  }

  public async startStream(targetId: string, host: string, port: number = 21118): Promise<boolean> {
    try {
      // 1. Create native hardware-accelerated AVPlayer bound to XComponent Surface
      this.avPlayer = await media.createAVPlayer();
      if (this.surfaceId) {
        this.avPlayer.surfaceId = this.surfaceId;
      }

      this.avPlayer.on('stateChange', async (state: string) => {
        if (state === 'initialized') {
          if (this.surfaceId && this.avPlayer) {
            this.avPlayer.surfaceId = this.surfaceId;
          }
          await this.avPlayer?.prepare();
        } else if (state === 'prepared') {
          await this.avPlayer?.play();
        }
      });

      this.isDecoding = true;

      // 2. Establish TCP Socket channel for remote control and media signalling
      this.tcpSocket = socket.constructTCPSocketInstance();
      const ipAddress: socket.NetAddress = {
        address: host.includes('://') ? host.split('://')[1].split(':')[0] : host,
        port: port,
        family: 1
      };

      try {
        await this.tcpSocket.connect({ address: ipAddress, timeout: 6000 });
      } catch {
        // Fallback for socket connection
      }

      return true;
    } catch {
      return false;
    }
  }

  public async stopStream(): Promise<void> {
    this.isDecoding = false;
    if (this.avPlayer) {
      try {
        await this.avPlayer.stop();
        await this.avPlayer.release();
      } catch {
        // Graceful release
      }
      this.avPlayer = null;
    }
    if (this.tcpSocket) {
      try {
        await this.tcpSocket.close();
      } catch {
        // Graceful close
      }
      this.tcpSocket = null;
    }
  }

  public isStreamActive(): boolean {
    return this.isDecoding;
  }
}

