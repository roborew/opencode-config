# HTML Report Format

The architectural review is rendered as a single self-contained HTML file. Tailwind and Mermaid both come from CDNs. Mermaid handles graph-shaped diagrams reliably; hand-built divs and inline SVG handle more editorial visuals such as mass diagrams and cross-sections. Mix the two.

## Scaffold

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Architecture review — {{repo name}}</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script type="module">
      import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
      mermaid.initialize({ startOnLoad: true, theme: "neutral", securityLevel: "loose" });
    </script>
    <style>
      .seam { stroke-dasharray: 4 4; }
      .leak { stroke: #dc2626; }
      .deep { background: linear-gradient(135deg, #0f172a, #1e293b); }
    </style>
  </head>
  <body class="bg-stone-50 text-slate-900 font-sans">
    <main class="max-w-5xl mx-auto px-6 py-12 space-y-12">
      <header>...</header>
      <section id="candidates" class="space-y-10">...</section>
      <section id="top-recommendation">...</section>
    </main>
  </body>
</html>
```

## Header

Repo name, date, and a compact legend: solid box = module, dashed line = seam, red arrow = leakage, thick dark box = deep module. No introduction paragraph.

## Candidate card

Each candidate is one card:

- **ID and title** — short, names the deepening.
- **Badge row** — recommendation strength (`Strong`, `Worth exploring`, `Speculative`) plus dependency category (`in-process`, `local-substitutable`, `ports & adapters`, `mock`).
- **Files** — monospaced list.
- **Before / After diagram** — the centrepiece.
- **Problem** — one sentence.
- **Solution** — one sentence.
- **Wins** — bullets, no more than six words each.
- **ADR callout** — one line when relevant.

No long paragraphs. If the diagram needs a paragraph to be understood, redraw the diagram.

## Diagram patterns

### Mermaid graph

Use `flowchart`, `graph`, or sequence diagrams when dependencies or call flow are the point.

```html
<div class="rounded-lg border border-slate-200 bg-white p-4">
  <pre class="mermaid">
    flowchart LR
      A[OrderHandler] --> B[OrderValidator]
      B --> C[OrderRepo]
      C -.leak.-> D[PricingClient]
      classDef leak stroke:#dc2626,stroke-width:2px;
      class C,D leak
  </pre>
</div>
```

### Hand-built boxes-and-arrows

Use bordered divs and inline SVG arrows when Mermaid's layout fights the story, especially when the "after" view should be one thick-bordered deep module with faded internals.

### Cross-section

Stack horizontal bands to show layered shallowness: before has many thin bands; after has one thick band labelled with the consolidated responsibility.

### Mass diagram

Show interface surface area beside implementation. Before: interface nearly as large as implementation. After: interface short, implementation tall.

### Call-graph collapse

Before: tree of calls as nested boxes. After: same tree collapsed into one module, with internal calls faded.

## Top recommendation section

One larger card. Candidate id, candidate name, one sentence on why, and anchor link to its card.

## Tone

Plain English, concise, with architectural nouns and verbs from [LANGUAGE.md](LANGUAGE.md).

Use exactly: module, interface, implementation, depth, deep, shallow, seam, adapter, leverage, locality.

Never substitute: component, service, unit, API, signature, boundary, layer, wrapper.

Good phrasing:

- "Order intake module is shallow — interface nearly matches the implementation."
- "Pricing leaks across the seam."
- "Deepen: one interface, one place to test."
- "Two adapters justify the seam: HTTP in prod, in-memory in tests."

Wins bullets should name glossary gains:

- "locality: bugs concentrate"
- "leverage: one interface"
- "interface shrinks"
- "tests cross one seam"
