// Geometry, random drift and luminance stops follow Android's LoginRibbonRenderer.
class RibbonSample {
  x: number = 0; y: number = 0; nx: number = 0; ny: number = 0; width: number = 0; bias: number = 0; scatter: number = 0;
}
@Component
export struct LoginBackdrop {
  @StorageLink('foreground') @Watch('updateActivity') foreground: boolean = true;
  @StorageLink('reduceMotion') @Watch('updateActivity') reduceMotion: boolean = false;
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private timer: number = -1; private started: number = Date.now(); private elapsed: number = 0;
  private seed: number = Math.floor(Math.random() * 100000); private ready: boolean = false;
  private cache: Map<number, number> = new Map();
  aboutToDisappear(): void { this.ready = false; this.stop(); }
  private stop(): void { if (this.timer >= 0) clearInterval(this.timer); this.timer = -1; }
  private updateActivity(): void {
    this.stop();
    if (this.reduceMotion) { if (this.ready) this.draw(0); return; }
    if (this.foreground && this.ready) {
      this.started = Date.now() - this.elapsed;
      this.timer = setInterval(() => { this.elapsed = Date.now() - this.started; this.draw(this.elapsed / 1000); }, 50);
    }
  }
  private drift(time: number, channel: number): number {
    const cached = this.cache.get(channel); if (cached !== undefined) return cached;
    const position = time / (9 + channel % 7 * 1.3) + channel * .37;
    const step = Math.floor(position), f = position - step;
    const eased = f * f * f * (f * (f * 6 - 15) + 10);
    const random = (at: number): number => { const x = Math.sin((this.seed + at * 1013 + channel * 7919) * 12.9898) * 43758.5453; return x - Math.floor(x); };
    const result = (random(step) + (random(step + 1) - random(step)) * eased) * 2 - 1;
    this.cache.set(channel, result); return result;
  }
  private variation(position: number, time: number, channel: number): number {
    const step = Math.floor(position), fraction = position - step, eased = fraction * fraction * (3 - 2 * fraction);
    const from = this.drift(time, channel + step);
    return from + (this.drift(time, channel + step + 1) - from) * eased;
  }
  private contour(samples: RibbonSample[], short: number, scale: number, dispersion: number, offset: number = 0): void {
    const c = this.context; c.beginPath();
    for (let side = 1; side >= -1; side -= 2) {
      for (let i = 0; i < samples.length; i++) {
        const s = samples[side > 0 ? i : samples.length - 1 - i], spread = short * dispersion;
        const radius = s.width * scale * (.5 + side * s.bias * .24) + spread * (.65 + s.scatter * side * .35);
        const d = side * radius + s.width * offset + spread * s.scatter;
        if (side > 0 && i === 0) c.moveTo(s.x + s.nx * d, s.y + s.ny * d);
        else c.lineTo(s.x + s.nx * d, s.y + s.ny * d);
      }
    }
    c.closePath(); c.fill();
  }
  private draw(time: number): void {
    const c = this.context, w = c.width, h = c.height, short = Math.min(w, h);
    if (!w || !h) return;
    // API 12: reset the backing buffer, paths and drawing state for each full repaint.
    c.reset();
    c.globalCompositeOperation = 'source-over'; c.fillStyle = '#000000'; c.globalAlpha = 1; c.shadowBlur = 0; c.fillRect(0, 0, w, h); this.cache.clear();
    for (let index = 0; index < 4; index++) {
      const channel = index * 100, lane = [-.08, .62, 1.02, .28][index], direction = index % 2 === 0 ? 1 : -1;
      const width = short * [.56, .38, .29, .19][index] * (1 + this.drift(time, channel + 8) * .18);
      const x0 = w * (lane + this.drift(time, channel) * .44), y0 = h * -.35;
      const x1 = w * (lane + direction * .65 + this.drift(time, channel + 2) * .75), y1 = h * (.18 + this.drift(time, channel + 3) * .16);
      const x2 = w * (1 - lane - direction * .65 + this.drift(time, channel + 4) * .75), y2 = h * (.72 + this.drift(time, channel + 5) * .2);
      const x3 = w * (1 - lane + this.drift(time, channel + 1) * .55), y3 = h * 1.35;
      const samples: RibbonSample[] = [];
      for (let step = 0; step <= 80; step++) {
        const t = step / 80, u = 1 - t, along = t + time * .012;
        const bend = this.variation(along * 4.3, time, channel + 12), detail = this.variation(along * 10.7, time, channel + 25);
        const breadth = this.variation(along * 5.1, time, channel + 40);
        const dx = 3 * u * u * (x1 - x0) + 6 * u * t * (x2 - x1) + 3 * t * t * (x3 - x2);
        const dy = 3 * u * u * (y1 - y0) + 6 * u * t * (y2 - y1) + 3 * t * t * (y3 - y2);
        const length = Math.max(1, Math.hypot(dx, dy)), s = new RibbonSample();
        s.nx = dy / length; s.ny = -dx / length;
        s.x = u * u * u * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3 + s.nx * short * (bend * .23 + detail * .045);
        s.y = u * u * u * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3 + s.ny * short * (bend * .23 + detail * .045);
        s.width = width * (.16 + Math.pow((breadth + 1) * .5, 1.6) * 1.4);
        s.bias = this.variation(along * 7.4, time, channel + 55); s.scatter = this.variation(along * 3.8, time, channel + 70); samples.push(s);
      }
      const light = this.drift(time, channel + 6), intensity = .72 + this.drift(time, channel + 7) * .16;
      const surface = c.createLinearGradient(w * (-.2 + light * .35), h * -.1, w * (1.1 + light * .25), h * 1.05);
      surface.addColorStop(0, 'transparent'); surface.addColorStop(.18, 'rgba(255,255,255,.12)');
      surface.addColorStop(.35, `rgba(255,255,255,${intensity * .64})`); surface.addColorStop(.48, `rgba(255,255,255,${intensity})`);
      surface.addColorStop(.65, 'rgba(31,31,31,.88)'); surface.addColorStop(.83, 'rgba(255,255,255,.22)'); surface.addColorStop(1, 'transparent');
      c.fillStyle = surface; c.globalCompositeOperation = 'screen'; c.globalAlpha = .18;
      c.shadowColor = 'rgba(255,255,255,.2)'; c.shadowBlur = short * .14; this.contour(samples, short, 1.5, .2);
      c.globalCompositeOperation = 'source-over'; c.globalAlpha = 1; c.shadowBlur = short * .045; this.contour(samples, short, 1, 0);
      c.globalCompositeOperation = 'screen'; c.globalAlpha = .42; c.shadowBlur = short * .035; this.contour(samples, short, .24, .025, -.2);
    }
    c.globalCompositeOperation = 'source-over'; c.globalAlpha = 1; c.shadowBlur = 0;
    const mask = c.createLinearGradient(0, 0, 0, h);
    mask.addColorStop(0, 'rgba(0,0,0,.24)'); mask.addColorStop(.2, 'transparent'); mask.addColorStop(.48, 'transparent'); mask.addColorStop(1, 'rgba(0,0,0,.66)');
    c.fillStyle = mask; c.fillRect(0, 0, w, h);
  }
  build() {
    Stack() {
      // The deliberately soft background needs no full-resolution raster surface.
      // Keep geometry proportional while bounding the blur/shadow render buffers.
      Canvas(this.context).width('50%').height('50%').blur(4.5).scale({ x: 2, y: 2 })
        .onReady(() => { this.ready = true; this.draw(0); this.updateActivity(); })
    }.width('100%').height('100%').clip(true).hitTestBehavior(HitTestMode.None)
  }
}
