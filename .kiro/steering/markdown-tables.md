---
inclusion: fileMatch
fileMatchPattern: "src/content/docs/**"
---

# Tables in MDX

Markdown pipe tables do not render reliably in `.mdx` files that import custom components such as
`Tooltip` — the MDX parser treats the pipes as text.

## Rule

- Plain `.mdx` page with no component imports → Markdown pipe tables are fine.
- Page that imports `Tooltip` or another component into the table → use an HTML `<table>`.

```mdx
<table>
  <thead>
    <tr>
      <th>Setting</th>
      <th>Value</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>
        <Tooltip term="data-freshness" />
      </td>
      <td>
        <code>300</code> to <code>900</code> seconds
      </td>
    </tr>
  </tbody>
</table>
```

## Pipe table hygiene

When pipe tables are used, keep separator rows spaced and aligned (`| ---- | ---- |`) and escape
literal pipes inside cells as `\|`. The `format-markdown-tables` hook repairs these on save.
