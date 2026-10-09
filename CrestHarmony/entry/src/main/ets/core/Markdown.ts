export interface Inline { text: string; bold: boolean; italic: boolean; code: boolean; strike: boolean; link: string }
export class Block {
  kind: string; text: string; level: number = 0; start: number = 1; language: string = '';
  items: string[] = []; headers: string[] = []; rows: string[][] = [];
  constructor(kind: string, text: string = '') { this.kind = kind; this.text = text; }
}
// Match iOS: freeze blocks ending at blank lines outside code fences; only parse the streaming tail.
export class MarkdownBlockCache {
  blocks: Block[] = [];
  private source: string = '';
  private committed: Block[] = [];
  private pending: string = '';
  private wasStreaming: boolean = false;
  update(content: string, streaming: boolean): void {
    if (content === this.source && streaming === this.wasStreaming) return;
    if (!streaming) {
      this.source = content; this.committed = []; this.pending = '';
      this.blocks = markdown(content); this.wasStreaming = false; return;
    }
    if (this.wasStreaming && content.startsWith(this.source)) this.pending += content.slice(this.source.length);
    else { this.committed = []; this.pending = content; }
    this.source = content; this.wasStreaming = true;
    let start = 0, boundary = 0, insideFence = false;
    for (let end = this.pending.indexOf('\n'); end >= 0; end = this.pending.indexOf('\n', start)) {
      const line = this.pending.slice(start, end).trim();
      if (line.startsWith('```')) insideFence = !insideFence;
      else if (!line && !insideFence) boundary = end + 1;
      start = end + 1;
    }
    if (boundary > 0) {
      this.committed.push(...markdown(this.pending.slice(0, boundary)));
      this.pending = this.pending.slice(boundary);
    }
    this.blocks = this.committed.concat(markdown(this.pending));
  }
}
function cells(line: string): string[] {
  if (!line.includes('|')) return [];
  const values = line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map((s: string) => s.trim());
  return values.length > 1 ? values : [];
}
export function markdown(source: string): Block[] {
  const lines = source.replace(/\r\n/g, '\n').split('\n'), blocks: Block[] = [];
  let i = 0, paragraph: string[] = [];
  const flush = (): void => { if (paragraph.length) blocks.push(new Block('paragraph', paragraph.join('\n'))); paragraph = []; };
  while (i < lines.length) {
    const line = lines[i].trim();
    if (!line) { flush(); i++; continue; }
    if (line.startsWith('```')) {
      flush(); const block = new Block('code'); block.language = line.slice(3).trim(); i++;
      const code: string[] = [];
      while (i < lines.length && !lines[i].trim().startsWith('```')) code.push(lines[i++]);
      if (i < lines.length) i++; block.text = code.join('\n'); blocks.push(block); continue;
    }
    const headers = cells(line), separator = i + 1 < lines.length ? cells(lines[i + 1]) : [];
    if (headers.length && headers.length === separator.length && separator.every((c: string) => /^:?-{3,}:?$/.test(c))) {
      flush(); const block = new Block('table'); block.headers = headers; i += 2;
      while (i < lines.length && cells(lines[i]).length) block.rows.push(cells(lines[i++]));
      blocks.push(block); continue;
    }
    const heading = /^(#{1,6})\s+(.+)$/.exec(line);
    if (heading) { flush(); const block = new Block('heading', heading[2]); block.level = heading[1].length; blocks.push(block); i++; continue; }
    if (/^(\*{3,}|-{3,}|_{3,})$/.test(line.replace(/\s/g, ''))) { flush(); blocks.push(new Block('divider')); i++; continue; }
    const ordered = /^(\d+)\.\s+/.exec(line), bullet = /^[-*+]\s+/.test(line);
    if (ordered || bullet) {
      flush(); const block = new Block(ordered ? 'ordered' : 'list'); block.start = ordered ? Number(ordered[1]) : 1;
      const pattern = ordered ? /^\d+\.\s+/ : /^[-*+]\s+/;
      while (i < lines.length && pattern.test(lines[i].trim())) block.items.push(lines[i++].trim().replace(pattern, ''));
      blocks.push(block); continue;
    }
    if (line.startsWith('>')) {
      flush(); const quotes: string[] = [];
      while (i < lines.length && lines[i].trim().startsWith('>')) quotes.push(lines[i++].trim().slice(1).trim());
      blocks.push(new Block('quote', quotes.join('\n'))); continue;
    }
    paragraph.push(line); i++;
  }
  flush(); return blocks;
}
// Native text only. HTML is never executed, and links are separately scheme-checked before opening.
export function inline(source: string, bold: boolean = false, italic: boolean = false): Inline[] {
  const pattern = /(`[^`]+`|\*\*[^*]+\*\*|__[^_]+__|~~[^~]+~~|\*[^*]+\*|_[^_]+_|\[[^\]]+\]\([^\s)]+\))/g;
  const result: Inline[] = []; let cursor = 0; let match: RegExpExecArray | null;
  while ((match = pattern.exec(source)) !== null) {
    if (match.index > cursor) result.push({ text: source.slice(cursor, match.index), bold: bold, italic: italic, code: false, strike: false, link: '' });
    const token = match[0];
    const link = /^\[([^\]]+)\]\(([^)]+)\)$/.exec(token);
    if (link) result.push({ text: link[1], bold: bold, italic: italic, code: false, strike: false, link: link[2] });
    else if (token.startsWith('**') || token.startsWith('__')) result.push(...inline(token.slice(2, -2), true, italic));
    else result.push({ text: token.startsWith('~~') ? token.slice(2, -2) : token.slice(1, -1), bold: bold,
      italic: italic || token.startsWith('*') || token.startsWith('_'), code: token.startsWith('`'), strike: token.startsWith('~~'), link: '' });
    cursor = match.index + token.length;
  }
  if (cursor < source.length) result.push({ text: source.slice(cursor), bold: bold, italic: italic, code: false, strike: false, link: '' });
  return result;
}
