# Docs Experience: On-Demand, Search-First

Large Python libraries make full docs generation slow and noisy. The new system makes docs a queryable cache rather than a single massive build.

## UX Goals

- Fast discovery (`__search__/1` and CLI search)
- Per-symbol HTML within milliseconds
- Works in IEx and in the browser
- No need to generate full docs for the entire library

## The On-Demand Model

1. **Build a small search index** from introspection metadata
2. **Render HTML for a symbol only when requested**
3. **Cache that HTML** and link it from a lightweight docs portal

The docs portal is a minimal ExDoc site with dynamic links to cached pages.

## User Interfaces

### IEx

```
Snakepit.doc("sympy.expand")
Snakepit.search("sympy", "integrate")
```

### CLI

```
mix snakepit.docs sympy.expand
mix snakepit.search sympy integrate
```

### Browser

```
open doc/snakepit/index.html
```

## Rendering Strategy

Python docstrings are usually reStructuredText, not Markdown. The rendering pipeline should be:

1. Parse RST to HTML using `docutils` (Python)
2. Convert to Markdown only if ExDoc requires it
3. Escape only unsafe HTML, never raw code blocks or backticks

This avoids the broken output seen when escaping everything. It also enables proper rendering of:

- Inline code: ``foo``
- Autolinks: `<https://foo>`
- Math: `$x^2$` or `.. math::` blocks

## Math Rendering

- Use `ex_doc` with `math_engine: :katex`
- Convert RST math to `$...$` or `\[...\]`
- Include KaTeX assets in the docs portal

## Search Index Design

A minimal index can be built from metadata:

```
{
  "library": "sympy",
  "symbols": [
    {"name": "expand", "kind": "function", "summary": "Expand expression"}
  ]
}
```

The search index is lightweight and built quickly, even for large libraries.

## Compatibility With `mix docs`

- `mix docs` should only document Snakepit and Snakebridge core modules
- Library docs live in `doc/snakepit/`
- A link from the main ExDoc homepage points to the Snakepit docs portal

