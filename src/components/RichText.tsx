import { Fragment } from 'react'
import { parseBlocks, type Inline } from '../lib/richText'

function Inlines({ parts }: { parts: Inline[] }) {
  return (
    <>
      {parts.map((p, i) => (p.italic ? <em key={i}>{p.text}</em> : <Fragment key={i}>{p.text}</Fragment>))}
    </>
  )
}

// Texto de una clase. React escapa todo: nunca se interpreta como HTML.
export function RichText({ source }: { source: string }) {
  const blocks = parseBlocks(source)
  if (!blocks.length) return null
  return (
    <div className="rich-text">
      {blocks.map((b, i) => {
        if (b.type === 'heading') {
          return (
            <h2 key={i} className="h-md">
              <Inlines parts={b.content} />
            </h2>
          )
        }
        if (b.type === 'list') {
          return (
            <ul key={i}>
              {b.items.map((item, j) => (
                <li key={j}>
                  <Inlines parts={item} />
                </li>
              ))}
            </ul>
          )
        }
        return (
          <p key={i}>
            {b.lines.map((line, j) => (
              <Fragment key={j}>
                {j > 0 && <br />}
                <Inlines parts={line} />
              </Fragment>
            ))}
          </p>
        )
      })}
    </div>
  )
}
