// Texto de las clases, con el mismo formato que los textos largos del sitio (data-copy-block):
// renglón vacío = párrafo nuevo, "## " = título, "- " = lista, *texto* = cursiva.
// Nunca se interpreta como HTML: React escapa todo.

export type Inline = { text: string; italic: boolean }
export type Block =
  | { type: 'heading'; content: Inline[] }
  | { type: 'paragraph'; lines: Inline[][] }
  | { type: 'list'; items: Inline[][] }

export function parseInline(text: string): Inline[] {
  const parts: Inline[] = []
  const re = /\*([^*\n]+)\*/g
  let last = 0
  for (let m = re.exec(text); m; m = re.exec(text)) {
    if (m.index > last) parts.push({ text: text.slice(last, m.index), italic: false })
    parts.push({ text: m[1] as string, italic: true })
    last = m.index + m[0].length
  }
  if (last < text.length) parts.push({ text: text.slice(last), italic: false })
  return parts
}

export function parseBlocks(source: string): Block[] {
  const blocks: Block[] = []
  const chunks = source.replace(/\r\n?/g, '\n').split(/\n\s*\n/)
  for (const chunk of chunks) {
    const lines = chunk.split('\n').map((l) => l.trimEnd()).filter((l) => l.trim() !== '')
    if (lines.length === 0) continue
    let paragraph: string[] = []
    let list: string[] = []
    const flushParagraph = () => {
      if (paragraph.length) blocks.push({ type: 'paragraph', lines: paragraph.map(parseInline) })
      paragraph = []
    }
    const flushList = () => {
      if (list.length) blocks.push({ type: 'list', items: list.map(parseInline) })
      list = []
    }
    for (const raw of lines) {
      const line = raw.trim()
      if (line.startsWith('## ')) {
        flushParagraph()
        flushList()
        blocks.push({ type: 'heading', content: parseInline(line.slice(3).trim()) })
      } else if (line.startsWith('- ')) {
        flushParagraph()
        list.push(line.slice(2).trim())
      } else {
        flushList()
        paragraph.push(line)
      }
    }
    flushParagraph()
    flushList()
  }
  return blocks
}
