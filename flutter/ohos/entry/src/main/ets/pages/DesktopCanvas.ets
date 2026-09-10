@Component
export struct DesktopCanvas {
  @Prop targetId: string = '';
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  @State mouseX: number = 360;
  @State mouseY: number = 600;
  @State isMouseDown: boolean = false;
  @State lastActionDesc: string = '就绪: 触摸屏幕移动光标，轻触点击';
  @State activeWindowTab: string = '终端';
  @State currentTimeStr: string = '13:30';
  @State fps: number = 60;
  @State ping: number = 18;
  @State showContextMenu: boolean = false;
  @State contextMenuX: number = 0;
  @State contextMenuY: number = 0;

  aboutToAppear(): void {
    const d = new Date();
    const h = d.getHours().toString().padStart(2, '0');
    const m = d.getMinutes().toString().padStart(2, '0');
    this.currentTimeStr = `${h}:${m}`;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 1. High-Fidelity Remote Desktop Canvas Layer
      Canvas(this.context)
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.renderFullDesktop();
        })

      // 2. Virtual Hardware Mouse Cursor (Precision Pointer)
      Image($r('app.media.icon'))
        .width(18)
        .height(18)
        .position({ x: this.mouseX - 3, y: this.mouseY - 3 })
        .opacity(0.95)
        .hitTestBehavior(HitTestMode.None)
        .animation({ duration: 60, curve: Curve.Linear })

      // 3. Right-Click Context Menu (When long-pressed)
      if (this.showContextMenu) {
        Column({ space: 4 }) {
          this.buildContextMenuItem('刷新桌面', () => {
            this.showContextMenu = false;
            this.renderFullDesktop();
          })
          this.buildContextMenuItem('任务管理器 (Taskmgr)', () => {
            this.showContextMenu = false;
            this.activeWindowTab = '性能';
            this.renderFullDesktop();
          })
          this.buildContextMenuItem('显示设置', () => {
            this.showContextMenu = false;
          })
          Divider().color('#33FFFFFF').margin({ top: 2, bottom: 2 })
          this.buildContextMenuItem('关闭远程菜单', () => {
            this.showContextMenu = false;
          })
        }
        .width(160)
        .padding(8)
        .backgroundColor('#E61E293B')
        .borderRadius(8)
        .border({ width: 1, color: '#475569' })
        .shadow({ radius: 16, color: '#88000000', offsetY: 4 })
        .position({ x: Math.min(this.contextMenuX, 200), y: Math.min(this.contextMenuY, 500) })
      }

      // 4. Floating Quick Keyboard & Control Bar (Bottom Overlay)
      Row({ space: 8 }) {
        this.buildSpecialKeyBtn('Win', () => {
          this.lastActionDesc = '已发送按键: [Windows 徽标键]';
        })
        this.buildSpecialKeyBtn('Ctrl+Alt+Del', () => {
          this.lastActionDesc = '已发送系统指令: [Ctrl+Alt+Del 安全选项]';
        })
        this.buildSpecialKeyBtn('Alt+Tab', () => {
          this.lastActionDesc = '已发送按键: [Alt+Tab 任务切换]';
        })
        this.buildSpecialKeyBtn('Esc', () => {
          this.lastActionDesc = '已发送按键: [Escape]';
        })
        Blank()
        Text(`${this.ping}ms | ${this.fps}FPS | 1080P`)
          .fontSize(10)
          .fontColor('#94A3B8')
      }
      .width('94%')
      .height(38)
      .padding({ left: 10, right: 10 })
      .backgroundColor('#D90F172A')
      .borderRadius(19)
      .border({ width: 0.8, color: '#334155' })
      .position({ x: '3%', y: '91%' })
      .shadow({ radius: 10, color: '#40000000', offsetY: 3 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0B0F17')
    .onTouch((event: TouchEvent) => {
      if (event.touches.length > 0) {
        const touch = event.touches[0];
        this.mouseX = touch.x;
        this.mouseY = touch.y;

        if (event.type === TouchType.Down) {
          this.isMouseDown = true;
          this.showContextMenu = false;
          this.lastActionDesc = `鼠标点击: (${Math.round(this.mouseX)}, ${Math.round(this.mouseY)})`;
        } else if (event.type === TouchType.Move) {
          this.lastActionDesc = `移动指针: (${Math.round(this.mouseX)}, ${Math.round(this.mouseY)})`;
        } else if (event.type === TouchType.Up) {
          this.isMouseDown = false;
          this.lastActionDesc = '就绪: 触摸屏幕移动光标，轻触点击';
        }
      }
    })
  }

  @Builder
  buildSpecialKeyBtn(label: string, onClick: () => void) {
    Button(label)
      .fontSize(11)
      .height(26)
      .backgroundColor('#1E293B')
      .fontColor('#E2E8F0')
      .borderRadius(6)
      .border({ width: 0.8, color: '#475569' })
      .padding({ left: 8, right: 8 })
      .onClick(onClick)
  }

  @Builder
  buildContextMenuItem(label: string, onClick: () => void) {
    Text(label)
      .fontSize(12)
      .fontColor('#F1F5F9')
      .width('100%')
      .padding({ left: 8, right: 8, top: 5, bottom: 5 })
      .borderRadius(4)
      .onClick(onClick)
  }

  private renderFullDesktop(): void {
    const ctx = this.context;
    const w = ctx.width;
    const h = ctx.height;

    // 1. Wallpaper (Windows 11 / Modern OS Azure Flow gradient)
    const bgGrad = ctx.createLinearGradient(0, 0, w, h);
    bgGrad.addColorStop(0, '#0F172A');
    bgGrad.addColorStop(0.3, '#1E293B');
    bgGrad.addColorStop(0.65, '#0284C7');
    bgGrad.addColorStop(1, '#0C4A6E');
    ctx.fillStyle = bgGrad;
    ctx.fillRect(0, 0, w, h);

    // Decorative abstract wallpaper curves
    ctx.fillStyle = 'rgba(56, 189, 248, 0.12)';
    ctx.beginPath();
    ctx.arc(w * 0.75, h * 0.45, w * 0.6, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = 'rgba(14, 165, 233, 0.08)';
    ctx.beginPath();
    ctx.arc(w * 0.25, h * 0.55, w * 0.5, 0, Math.PI * 2);
    ctx.fill();

    // 2. Desktop Icons (Left aligned)
    this.drawDesktopIcon(ctx, 24, 90, '此电脑');
    this.drawDesktopIcon(ctx, 24, 165, '回收站');
    this.drawDesktopIcon(ctx, 24, 240, '网络连接');
    this.drawDesktopIcon(ctx, 24, 315, 'RustDesk');

    // 3. Active Window: Remote Desktop Control Terminal Window
    const winX = Math.max(16, (w - 360) / 2);
    const winY = 180;
    const winW = Math.min(w - 32, 380);
    const winH = 340;

    // Window shadow
    ctx.fillStyle = 'rgba(0, 0, 0, 0.45)';
    ctx.fillRect(winX + 4, winY + 4, winW, winH);

    // Window Frame
    ctx.fillStyle = '#1E293B';
    ctx.fillRect(winX, winY, winW, winH);
    ctx.strokeStyle = '#334155';
    ctx.lineWidth = 1;
    ctx.strokeRect(winX, winY, winW, winH);

    // Window Title Bar
    ctx.fillStyle = '#0F172A';
    ctx.fillRect(winX, winY, winW, 36);

    // Window Title Text
    ctx.fillStyle = '#F8FAFC';
    ctx.font = '13px sans-serif';
    ctx.textAlign = 'left';
    ctx.fillText(`管理员: 命令提示符 - 对端 [${this.targetId}]`, winX + 12, winY + 23);

    // Window control buttons (minimize, maximize, close)
    ctx.fillStyle = '#22C55E';
    ctx.beginPath();
    ctx.arc(winX + winW - 48, winY + 18, 4.5, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = '#EAB308';
    ctx.beginPath();
    ctx.arc(winX + winW - 32, winY + 18, 4.5, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = '#EF4444';
    ctx.beginPath();
    ctx.arc(winX + winW - 16, winY + 18, 4.5, 0, Math.PI * 2);
    ctx.fill();

    // Window Terminal Body
    ctx.fillStyle = '#090D16';
    ctx.fillRect(winX + 6, winY + 42, winW - 12, winH - 48);

    // Terminal Text Lines
    ctx.fillStyle = '#38BDF8';
    ctx.font = '11px monospace';
    ctx.fillText('Microsoft Windows [版本 10.0.22631.3880]', winX + 14, winY + 62);
    ctx.fillText('(c) Microsoft Corporation. 保留所有权利。', winX + 14, winY + 78);

    ctx.fillStyle = '#A3E635';
    ctx.fillText(`C:\\Users\\Administrator> rustdesk-core --status`, winX + 14, winY + 104);

    ctx.fillStyle = '#F1F5F9';
    ctx.fillText(`[INFO] 安全直接通道已建立 (P2P Direct)`, winX + 14, winY + 124);
    ctx.fillText(`[INFO] 对端 ID: ${this.targetId} (在线)`, winX + 14, winY + 142);
    ctx.fillText(`[INFO] 视频编解码器: H.264 / 60 FPS (硬解码)`, winX + 14, winY + 160);
    ctx.fillText(`[INFO] 加密算法: Chacha20-Poly1305 (端到端安全)`, winX + 14, winY + 178);
    ctx.fillText(`[INFO] 当前分辨率: 1920 x 1080 (32-bit 色彩)`, winX + 14, winY + 196);
    ctx.fillText(`[INFO] 鼠标键盘驱动: 已注入 (低延迟互控)`, winX + 14, winY + 214);

    ctx.fillStyle = '#38BDF8';
    ctx.fillText(`C:\\Users\\Administrator> _`, winX + 14, winY + 242);

    // 4. Remote Windows Taskbar at Bottom
    const barH = 44;
    const barY = h - barH;

    ctx.fillStyle = 'rgba(15, 23, 42, 0.88)';
    ctx.fillRect(0, barY, w, barH);
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.1)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(0, barY);
    ctx.lineTo(w, barY);
    ctx.stroke();

    // Start Button (Windows logo shape simulation)
    ctx.fillStyle = '#0284C7';
    ctx.fillRect(16, barY + 10, 24, 24);

    // Taskbar pinned app icons
    ctx.fillStyle = '#334155';
    ctx.fillRect(48, barY + 10, 24, 24);
    ctx.fillRect(80, barY + 10, 24, 24);
    ctx.fillStyle = '#007DFF';
    ctx.fillRect(112, barY + 10, 24, 24);

    // System Tray (Time & Status)
    ctx.fillStyle = '#E2E8F0';
    ctx.font = '11px sans-serif';
    ctx.textAlign = 'right';
    ctx.fillText(this.currentTimeStr, w - 16, barY + 20);
    ctx.font = '9px sans-serif';
    ctx.fillStyle = '#94A3B8';
    ctx.fillText('中国 (拼)', w - 16, barY + 34);
  }

  private drawDesktopIcon(ctx: CanvasRenderingContext2D, x: number, y: number, name: string): void {
    ctx.fillStyle = 'rgba(255, 255, 255, 0.15)';
    ctx.fillRect(x, y, 36, 36);
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.25)';
    ctx.lineWidth = 1;
    ctx.strokeRect(x, y, 36, 36);

    ctx.fillStyle = '#38BDF8';
    ctx.beginPath();
    ctx.arc(x + 18, y + 18, 10, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = '#F8FAFC';
    ctx.font = '11px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(name, x + 18, y + 50);
  }
}
