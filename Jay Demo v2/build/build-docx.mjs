// Builds JAY DEMO v2\IMH-Option2-Dry-Run-and-Workflow.docx from build\content\*.md (read in name order).
// Run from the session folder:  node "JAY DEMO v2\build\build-docx.mjs"
// docx 9.5.1 is installed outside OneDrive (%LOCALAPPDATA%\imh-onsite-documents) or at DOCX_MODULE_ROOT.
//
// Content syntax (one block per line):
//   # Title {#id}   H1 with bookmark, new page, listed in Contents      ## / ###  H2 / H3
//   - item / "  - item"  bullets (2 levels)      1. item  numbered list (restarts per list)
//   | a | b |  table (first row = header; |---| skipped; \| = literal pipe; <br> = new line in a cell)
//   {widths: 1200 8160}  column widths for the next table (twips, must sum to 9360)
//   > SAY: text   blue "say this" box          > NOTE: text   amber note
//   ``` ... ```   code box (verbatim)
//   @title / @subtitle / @lead text   cover lines     @toc  contents page     @pagebreak
//   @img file.png | caption   image from ..\images     @evidence  every PNG in ..\images\evidence
//   @sql   rendered Unity Catalog SQL                 @policy mcp-key|mcp-limited|mcp-entra|model   rendered APIM policy
//   Inline: **bold**, `code`, ``code with `backticks` inside``
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const demo = path.resolve(here, '..');
const repo = path.resolve(demo, '..');
const images = path.join(demo, 'images');
const output = path.join(demo, 'IMH-Option2-Dry-Run-and-Workflow.docx');
const libraryRoot = process.env.DOCX_MODULE_ROOT ?? path.join(process.env.LOCALAPPDATA, 'imh-onsite-documents');
const require = createRequire(path.join(libraryRoot, 'package.json'));
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, ImageRun, Footer, PageNumber, AlignmentType, PageBreak,
  Table, TableRow, TableCell, WidthType, BorderStyle, ShadingType, LevelFormat, Bookmark, BookmarkStart, BookmarkEnd,
  InternalHyperlink,
} = require('docx');

const FULL = 9360;
const NAVY = '173753', BLUE = '2E75B6';
const edge = { style: BorderStyle.SINGLE, size: 4, color: 'CBD5E1' };
const none = { style: BorderStyle.NONE, size: 0, color: 'FFFFFF' };

// Live values for the APIM policy templates (no secrets: IDs and limits only).
const live = {
  CALLS: '30', TOOLCALLS: '3', QUOTA: '200', MAXROWS: '5', MAXBYTES: '20000', TPM: '20000',
  REWRITE: '/api/2.0/mcp/functions/imh_demo/clinical',
  RESOURCE: '2ff814a6-3304-4ab8-85cb-cd0e6f879c1d',
  CLIENT_ID: 'e983157d-68fc-430a-9ee8-cdf1efe4b68e',
  TENANT: '8d038e6a-9b7d-4cb8-bbcf-e84dff156478',
  CLIENTS: '\n        <application-id>dbd7f6a1-92a8-470b-a7bd-7bf2f947b6a7</application-id>\n      ',
  AUDIENCES: '\n        <audience>https://management.azure.com</audience>\n'
    + '        <audience>https://management.azure.com/</audience>\n      ',
};
const sqlVars = {
  catalog: 'imh_demo', schema: 'clinical',
  phi_full: 'imh_phi_full', analyst: 'imh_analyst', clinician_slc: 'imh_clinician_slc',
};

function smart(s) {
  return s
    .replace(/(^|[\s(\[{\u2014\u2013-])"/g, '$1\u201C').replace(/"/g, '\u201D')
    .replace(/(^|[\s(\[{\u2014\u2013-])'/g, '$1\u2018').replace(/'/g, '\u2019');
}

const INLINE = /(``.+?``|\*\*.+?\*\*|`[^`]+`)/g;
function runs(text, base = {}) {
  const codeSize = (base.size ?? 22) - 2;
  const out = [];
  for (const part of text.split(INLINE)) {
    if (!part) continue;
    if (part.length > 4 && part.startsWith('``') && part.endsWith('``')) {
      out.push(new TextRun({ ...base, text: part.slice(2, -2).trim(), font: 'Consolas', size: codeSize }));
    } else if (part.length > 4 && part.startsWith('**') && part.endsWith('**')) {
      out.push(...runs(part.slice(2, -2), { ...base, bold: true }));
    } else if (part.length > 2 && part.startsWith('`') && part.endsWith('`')) {
      out.push(new TextRun({ ...base, text: part.slice(1, -1), font: 'Consolas', size: codeSize }));
    } else {
      out.push(new TextRun({ ...base, text: smart(part) }));
    }
  }
  return out;
}

const para = (text, run = {}, extra = {}) =>
  new Paragraph({ spacing: { after: 120 }, ...extra, children: runs(text, run) });
const spacer = () => new Paragraph({ spacing: { before: 0, after: 0, line: 160 }, children: [] });

const toc = [];
let bookmarkCount = 0;
function heading(level, raw) {
  const m = raw.match(/^(.*?)\s*\{#([A-Za-z][\w-]*)\}\s*$/);
  const title = smart((m ? m[1] : raw).replace(/`/g, ''));
  if (level === 1) {
    if (!m) throw new Error(`H1 needs an {#id}: ${raw}`);
    // docx 9.5.1 gives every Bookmark w:id="1"; Word needs unique ids, so number them here.
    const bookmark = new Bookmark({ id: m[2], children: [new TextRun(title)] });
    bookmarkCount += 1;
    bookmark.start = new BookmarkStart(m[2], bookmarkCount);
    bookmark.end = new BookmarkEnd(bookmarkCount);
    return new Paragraph({ heading: HeadingLevel.HEADING_1, pageBreakBefore: true, children: [bookmark] });
  }
  return new Paragraph({ heading: level === 2 ? HeadingLevel.HEADING_2 : HeadingLevel.HEADING_3,
    keepNext: true, children: [new TextRun(title)] });
}

function equalWidths(n) {
  const w = Array(n).fill(Math.floor(FULL / n));
  w[n - 1] += FULL - w.reduce((a, b) => a + b, 0);
  return w;
}

function table(rows, widths) {
  const n = rows[0].length;
  widths ??= equalWidths(n);
  const sum = widths.reduce((a, b) => a + b, 0);
  if (widths.length !== n || sum !== FULL) {
    throw new Error(`Table widths ${widths.join(' ')} (sum ${sum}) do not fit ${n} columns / ${FULL}: ${rows[0].join(' | ')}`);
  }
  rows.forEach((r) => { if (r.length > n) throw new Error(`Row has ${r.length} cells, header has ${n}: ${r.join(' | ')}`); });
  return new Table({
    width: { size: FULL, type: WidthType.DXA }, columnWidths: widths,
    rows: rows.map((row, i) => new TableRow({
      tableHeader: i === 0, cantSplit: true,
      children: widths.map((w, c) => new TableCell({
        width: { size: w, type: WidthType.DXA },
        borders: { top: edge, bottom: edge, left: edge, right: edge },
        shading: { fill: i === 0 ? 'EAF1F8' : 'FFFFFF', type: ShadingType.CLEAR, color: 'auto' },
        margins: { top: 60, bottom: 60, left: 100, right: 100 },
        children: (row[c] ?? '').split('<br>').map((t) =>
          new Paragraph({ spacing: { after: 40 }, children: runs(t.trim(), { size: 19, bold: i === 0 || undefined }) })),
      })),
    })),
  });
}

// keep = do not split the box across pages (only for boxes that fit on one page).
function box(children, { fill, left, sides = none, keep = true }) {
  return [new Table({
    width: { size: FULL, type: WidthType.DXA }, columnWidths: [FULL],
    rows: [new TableRow({ cantSplit: keep, children: [new TableCell({
      width: { size: FULL, type: WidthType.DXA },
      borders: { top: sides, bottom: sides, right: sides, left },
      shading: { fill, type: ShadingType.CLEAR, color: 'auto' },
      margins: { top: 100, bottom: 100, left: 160, right: 160 },
      children,
    })] })],
  }), spacer()];
}

const codeBox = (text) => {
  const lines = text.replace(/\r/g, '').replace(/\t/g, '    ').split('\n');
  return box(lines.map((line) =>
    new Paragraph({ spacing: { after: 0 }, children: [new TextRun({ text: line.length ? line : ' ', font: 'Consolas', size: 16 })] })),
  { fill: 'F4F6F8', left: edge, sides: edge, keep: lines.length <= 45 });
};

const sayBox = (text) => box([new Paragraph({ spacing: { after: 0 }, children: [
  new TextRun({ text: 'SAY   ', bold: true, color: BLUE, size: 18 }),
  new TextRun('\u201C'), ...runs(text), new TextRun('\u201D'),
] })], { fill: 'EEF6FF', left: { style: BorderStyle.SINGLE, size: 24, color: BLUE } });

const noteBox = (text) => box([new Paragraph({ spacing: { after: 0 }, children: [
  new TextRun({ text: 'NOTE   ', bold: true, color: 'B45309', size: 18 }), ...runs(text),
] })], { fill: 'FFF7E6', left: { style: BorderStyle.SINGLE, size: 24, color: 'F59E0B' } });

let imageCount = 0;
function image(relative, caption) {
  const file = path.join(images, relative);
  if (!fs.existsSync(file)) throw new Error(`Missing image: ${file}`);
  const data = fs.readFileSync(file);
  if (data.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') throw new Error(`Not a PNG: ${file}`);
  const w = data.readUInt32BE(16), h = data.readUInt32BE(20);
  let width = Math.min(624, w), height = Math.round(width * h / w);
  if (height > 680) { height = 680; width = Math.round(680 * w / h); }
  const alt = caption.replace(/`/g, '');
  imageCount += 1;
  return [
    new Paragraph({ alignment: AlignmentType.CENTER, keepNext: true, spacing: { before: 120, after: 60 }, children: [
      new ImageRun({ type: 'png', data, transformation: { width, height },
        altText: { title: alt, description: alt, name: path.basename(file) } }),
    ] }),
    new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 240 },
      children: runs(caption, { italics: true, color: '555555', size: 18 }) }),
  ];
}

function evidence() {
  const dir = path.join(images, 'evidence');
  const files = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => /\.png$/i.test(f)).sort() : [];
  if (!files.length) {
    return [para('No dry-run screenshots yet. During the dry run, save PNGs as `JAY DEMO v2\\images\\evidence\\NN-<step>-<what>.png` and rebuild this document (Appendix D).')];
  }
  return files.flatMap((f) => image(path.join('evidence', f), `Dry run: ${f.replace(/\.png$/i, '').replace(/[-_]+/g, ' ')}`));
}

function ucSql() {
  const file = path.join(repo, 'infra', 'uc-agent-gateway', 'databricks', 'terraform', 'uc_objects.sql.tftpl');
  let sql = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
  sql = sql.replace(/INSERT INTO patients VALUES[\s\S]*?\);[ \t]*\r?\n/,
    '-- 12 synthetic rows are inserted here (SLC 4, OGDEN 3, PROVO 3, STGEORGE 2).\n'
    + '-- The live demo table was seeded during setup with other synthetic values; the rules are the same.\n');
  if (/INSERT INTO/i.test(sql)) throw new Error('Seed rows were not replaced in the SQL');
  sql = sql.replace(/\$\{(\w+)\}/g, (m, k) => {
    if (!(k in sqlVars)) throw new Error(`No value for ${m} in ${file}`);
    return sqlVars[k];
  });
  return sql.replace(/\r/g, '').trimEnd();
}

function policy(name) {
  const file = path.join(repo, 'infra', 'uc-agent-gateway', 'azure', `policy-${name}.xml`);
  let xml = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '').replace(/<!--[\s\S]*?-->/g, '');
  xml = xml.replace(/__([A-Z_]+?)__/g, (m, k) => {
    if (!(k in live)) throw new Error(`No live value for ${m} in ${file}`);
    return live[k];
  });
  return xml.replace(/\r/g, '').split('\n').filter((l) => l.trim()).join('\n');
}

function splitRow(line) {
  return line.trim().replace(/^\|/, '').replace(/\|$/, '').split(/(?<!\\)\|/).map((c) => c.replace(/\\\|/g, '|').trim());
}

function parse(src, name) {
  const lines = src.replace(/^\uFEFF/, '').replace(/\r/g, '').split('\n');
  const blocks = [];
  let i = 0, widths = null, m;
  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim() || line.startsWith('<!--')) { i += 1; continue; }
    if (line.startsWith('```')) {
      const body = [];
      i += 1;
      while (i < lines.length && !lines[i].startsWith('```')) body.push(lines[i++]);
      if (i >= lines.length) throw new Error(`${name}: unclosed code fence`);
      i += 1;
      blocks.push({ t: 'code', text: body.join('\n') });
    } else if ((m = line.match(/^\{widths:\s*([\d\s]+)\}\s*$/))) {
      widths = m[1].trim().split(/\s+/).map(Number);
      i += 1;
    } else if (line.startsWith('|')) {
      const rows = [];
      while (i < lines.length && lines[i].startsWith('|')) {
        const row = lines[i++];
        if (!/^\|\s*:?-{3,}/.test(row)) rows.push(splitRow(row));
      }
      blocks.push({ t: 'table', rows, widths });
      widths = null;
    } else if ((m = line.match(/^(#{1,3}) (.+)$/))) {
      blocks.push({ t: 'h', level: m[1].length, text: m[2] });
      i += 1;
    } else if (/^ {0,2}- /.test(line)) {
      const items = [];
      while (i < lines.length && /^ {0,2}- /.test(lines[i])) {
        const l = lines[i++];
        items.push({ level: l.startsWith('  ') ? 1 : 0, text: l.replace(/^ {0,2}- /, '') });
      }
      blocks.push({ t: 'bullets', items });
    } else if (/^\d+\. /.test(line)) {
      const items = [];
      while (i < lines.length && /^\d+\. /.test(lines[i])) items.push(lines[i++].replace(/^\d+\. /, ''));
      blocks.push({ t: 'numbers', items });
    } else if ((m = line.match(/^> (SAY|NOTE):\s*(.+)$/))) {
      blocks.push({ t: m[1].toLowerCase(), text: m[2] });
      i += 1;
    } else if ((m = line.match(/^@(\w+)\s*(.*)$/))) {
      blocks.push({ t: 'cmd', cmd: m[1], arg: m[2].trim() });
      i += 1;
    } else {
      blocks.push({ t: 'p', text: line.trim() });
      i += 1;
    }
  }
  if (widths) throw new Error(`${name}: {widths} not followed by a table`);
  return blocks;
}

let listInstance = 0;
// Lead-in lines (step labels, or text ending in a colon) stay on the same page as what follows them.
const KEEP_NEXT = /^\*\*(Open|Ask|Expect|Run|Add|Optional)\b|:\**\s*$/;
function render(b) {
  switch (b.t) {
    case 'h': return [heading(b.level, b.text)];
    case 'p': return [para(b.text, {}, KEEP_NEXT.test(b.text) ? { keepNext: true } : {})];
    case 'code': return codeBox(b.text);
    case 'say': return sayBox(b.text);
    case 'note': return noteBox(b.text);
    case 'table': return [table(b.rows, b.widths), spacer()];
    case 'bullets':
      return b.items.map((it, k) => new Paragraph({ numbering: { reference: 'bullets', level: it.level },
        spacing: { after: k === b.items.length - 1 ? 140 : 60 }, children: runs(it.text) }));
    case 'numbers': {
      listInstance += 1;
      const instance = listInstance;
      return b.items.map((text, k) => new Paragraph({ numbering: { reference: 'numbers', level: 0, instance },
        spacing: { after: k === b.items.length - 1 ? 140 : 60 }, children: runs(text) }));
    }
    case 'cmd': return command(b.cmd, b.arg);
    default: throw new Error(`Unknown block ${b.t}`);
  }
}

function command(cmd, arg) {
  switch (cmd) {
    case 'title': return [new Paragraph({ spacing: { before: 2400, after: 200 },
      children: [new TextRun({ text: smart(arg), bold: true, size: 56, color: NAVY })] })];
    case 'subtitle': return [new Paragraph({ spacing: { after: 160 },
      children: [new TextRun({ text: smart(arg), size: 34, color: BLUE })] })];
    case 'lead': return [new Paragraph({ spacing: { after: 480 },
      children: [new TextRun({ text: smart(arg), size: 26, color: '444444' })] })];
    case 'pagebreak': return [new Paragraph({ children: [new PageBreak()] })];
    case 'toc': return [
      new Paragraph({ heading: HeadingLevel.HEADING_1, pageBreakBefore: true, children: [new TextRun('Contents')] }),
      ...toc.map((e) => new Paragraph({ spacing: { after: 80 }, children: [
        new InternalHyperlink({ anchor: e.id, children: [new TextRun({ text: e.title, style: 'Hyperlink' })] }),
      ] })),
      para('Click a line to jump to it. In Word, the Navigation pane (View → Navigation Pane) shows every heading.',
        { italics: true, color: '555555', size: 18 }, { spacing: { before: 200 } }),
    ];
    case 'img': {
      const [file, ...rest] = arg.split('|');
      return image(file.trim(), rest.join('|').trim());
    }
    case 'evidence': return evidence();
    case 'sql': return codeBox(ucSql());
    case 'policy': return codeBox(policy(arg));
    default: throw new Error(`Unknown command @${cmd}`);
  }
}

const contentDir = path.join(here, 'content');
const files = fs.readdirSync(contentDir).filter((f) => f.endsWith('.md')).sort();
const blocks = files.flatMap((f) => parse(fs.readFileSync(path.join(contentDir, f), 'utf8'), f));

const sourceText = files.map((f) => fs.readFileSync(path.join(contentDir, f), 'utf8')).join('\n');
const leaks = [/-----BEGIN/, /\b(password|passwd|client[_ ]secret)\s*[:=]/i, /\b(?!01f1c5e2508a1326a03ad64e4d7fb1b5\b)[0-9a-f]{32}\b/i];
for (const re of leaks) if (re.test(sourceText)) throw new Error(`Content looks like it holds a secret (${re}); remove it.`);

for (const b of blocks) {
  if (b.t === 'h' && b.level === 1) {
    const m = b.text.match(/^(.*?)\s*\{#([A-Za-z][\w-]*)\}\s*$/);
    if (m) toc.push({ id: m[2], title: smart(m[1].replace(/`/g, '')) });
  }
}
const ids = new Set();
for (const e of toc) { if (ids.has(e.id)) throw new Error(`Duplicate H1 id ${e.id}`); ids.add(e.id); }

const children = blocks.flatMap(render);
const grey = { size: 16, color: '666666' };
const doc = new Document({
  creator: 'Jay Padhya',
  title: 'IMH onsite: Option 2 dry run and end-to-end workflow',
  description: 'Unity Catalog functions + MCP + API Management. Synthetic data, BrakeKat demo tenant.',
  styles: {
    default: { document: { run: { font: 'Arial', size: 22 } } },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: 'Arial', size: 32, bold: true, color: NAVY }, paragraph: { spacing: { before: 120, after: 200 }, outlineLevel: 0 } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: 'Arial', size: 26, bold: true, color: NAVY }, paragraph: { spacing: { before: 280, after: 120 }, outlineLevel: 1 } },
      { id: 'Heading3', name: 'Heading 3', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: 'Arial', size: 23, bold: true, color: NAVY }, paragraph: { spacing: { before: 220, after: 100 }, outlineLevel: 2 } },
    ],
  },
  numbering: { config: [
    { reference: 'bullets', levels: [
      { level: 0, format: LevelFormat.BULLET, text: '\u2022', alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 540, hanging: 270 } } } },
      { level: 1, format: LevelFormat.BULLET, text: '\u2013', alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 1080, hanging: 270 } } } },
    ] },
    { reference: 'numbers', levels: [
      { level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT,
        style: { paragraph: { indent: { left: 540, hanging: 360 } } } },
    ] },
  ] },
  sections: [{
    properties: { page: { size: { width: 12240, height: 15840 },
      margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 } } },
    footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [
      new TextRun({ ...grey, text: 'IMH Option 2 dry run \u00B7 synthetic data \u00B7 BrakeKat demo tenant \u00B7 Page ' }),
      new TextRun({ ...grey, children: [PageNumber.CURRENT] }),
    ] })] }) },
    children,
  }],
});

const buffer = await Packer.toBuffer(doc);
try {
  fs.writeFileSync(output, buffer);
} catch (err) {
  if (err.code === 'EBUSY' || err.code === 'EPERM') {
    console.error(`Close ${path.basename(output)} in Word, then run again.`);
    process.exit(1);
  }
  throw err;
}
console.log(`Wrote ${output}`);
console.log(`${files.length} content files, ${toc.length} sections, ${imageCount} images, ${buffer.length} bytes`);
