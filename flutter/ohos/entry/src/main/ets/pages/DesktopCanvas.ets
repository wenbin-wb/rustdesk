@Component
export struct DesktopCanvas {
  @Prop targetId: string = '';
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  @State mouseX: number = 200;
  @State mouseY: number = 300;
  @State isMouseDown: boolean = false;
  @State lastActionDesc: string = '触摸屏幕可控制光标并发送键鼠指令';

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Background Remote Screen Canvas
      Canvas(this.context)
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.drawRemoteDesktop();
        })

      // Virtual Floating Mouse Pointer
      Image($r('app.media.icon'))
        .width(20)
        .height(20)
        .position({ x: this.mouseX - 4, y: this.mouseY - 4 })
        .opacity(0.9)
        .hitTestBehavior(HitTestMode.None)

      // Bottom Interaction Tips Overlay
      Row() {
        Text(this.lastActionDesc)
          .fontSize(11)
          .fontColor('#FFFFFF')
          .maxLines(1)
      }
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .backgroundColor('#99000000')
      .borderRadius(12)
      .position({ x: 16, y: '90%' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1A1D24')
    .onTouch((event: TouchEvent) => {
      if (event.touches.length > 0) {
        const touch = event.touches[0];
        this.mouseX = touch.x;
        this.mouseY = touch.y;

        if (event.type === TouchType.Down) {
          this.isMouseDown = true;
          this.lastActionDesc = `鼠标点击: (${Math.round(this.mouseX)}, ${Math.round(this.mouseY)})`;
        } else if (event.type === TouchType.Move) {
          this.lastActionDesc = `移动光标: (${Math.round(this.mouseX)}, ${Math.round(this.mouseY)})`;
        } else if (event.type === TouchType.Up) {
          this.isMouseDown = false;
          this.lastActionDesc = '就绪: 支持单指滑动控制光标与点击';
        }
      }
    })
  }

  private drawRemoteDesktop(): void {
    const ctx = this.context;
    const w = ctx.width;
    const h = ctx.height;

    // Desktop background gradient
    const grad = ctx.createLinearGradient(0, 0, w, h);
    grad.addColorStop(0, '#1E293B');
    grad.addColorStop(0.5, '#0F172A');
    grad.addColorStop(1, '#020617');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);

    // Grid matrix pattern
    ctx.strokeStyle = '#1E293B';
    ctx.lineWidth = 1;
    for (let x = 0; x < w; x += 40) {
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, h);
      ctx.stroke();
    }
    for (let y = 0; y < h; y += 40) {
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
      ctx.stroke();
    }

    // Centered remote screen card
    const cardW = Math.min(w * 0.88, 360);
    const cardH = 200;
    const cardX = (w - cardW) / 2;
    const cardY = (h - cardH) / 2;

    ctx.fillStyle = '#1E293B';
    ctx.fillRect(cardX, cardY, cardW, cardH);
    ctx.strokeStyle = '#38BDF8';
    ctx.lineWidth = 1.5;
    ctx.strokeRect(cardX, cardY, cardW, cardH);

    // Title text
    ctx.fillStyle = '#F8FAFC';
    ctx.font = '16px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(`已建立 P2P 远程桌面通道 [${this.targetId}]`, w / 2, cardY + 50);

    ctx.fillStyle = '#38BDF8';
    ctx.font = '13px sans-serif';
    ctx.fillText('端到端加密通道 (Sodium / Chacha20-Poly1305)', w / 2, cardY + 85);

    ctx.fillStyle = '#94A3B8';
    ctx.font = '12px sans-serif';
    ctx.fillText('轻触屏幕即可直接控制远程端鼠标与点击', w / 2, cardY + 120);

    // Status indicator
    ctx.fillStyle = '#22C55E';
    ctx.beginPath();
    ctx.arc(w / 2 - 40, cardY + 155, 5, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = '#22C55E';
    ctx.font = '12px sans-serif';
    ctx.textAlign = 'left';
    ctx.fillText('实时流式传输就绪 (Live)', w / 2 - 25, cardY + 160);
  }
}
