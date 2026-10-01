export function Brand({ size = 28 }: { size?: number }) {
  return (
    <span className="brand">
      <img src="/logo-icon-green.png" alt="" width={size} height={size} />
      <span className="brand-word">AVA</span>
      <span className="brand-product">Campus</span>
    </span>
  )
}
