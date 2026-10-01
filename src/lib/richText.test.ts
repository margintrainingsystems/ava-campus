import { parseBlocks, parseInline } from './richText'

describe('parseBlocks', () => {
  it('arma títulos, párrafos y listas con el formato del sitio', () => {
    const blocks = parseBlocks('## Objetivo\nAprender a *filtrar*.\nSegunda línea.\n\n- Uno\n- Dos\n\nCierre')
    expect(blocks).toEqual([
      { type: 'heading', content: [{ text: 'Objetivo', italic: false }] },
      {
        type: 'paragraph',
        lines: [
          [
            { text: 'Aprender a ', italic: false },
            { text: 'filtrar', italic: true },
            { text: '.', italic: false },
          ],
          [{ text: 'Segunda línea.', italic: false }],
        ],
      },
      { type: 'list', items: [[{ text: 'Uno', italic: false }], [{ text: 'Dos', italic: false }]] },
      { type: 'paragraph', lines: [[{ text: 'Cierre', italic: false }]] },
    ])
  })

  it('ignora renglones vacíos y saltos de línea de Windows', () => {
    expect(parseBlocks('\r\n\r\n  \r\n')).toEqual([])
    expect(parseBlocks('a\r\n\r\nb')).toHaveLength(2)
  })

  it('no interpreta HTML: queda como texto', () => {
    expect(parseInline('<img src=x onerror=alert(1)>')).toEqual([
      { text: '<img src=x onerror=alert(1)>', italic: false },
    ])
  })
})
