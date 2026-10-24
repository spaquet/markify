# Extra Mermaid cases

Cases beyond Ondine's examples: HTML labels, Unicode, styling, links, long labels, and config frontmatter.

## Flowchart with HTML and Unicode labels

```mermaid
flowchart TD
  A["Café<br/>naïve · 日本語"] --> B{"Ready? ✓"}
  B -->|"yes"| C["Ship 🚀"]
  B -->|no| A
```

## Styled flowchart

```mermaid
flowchart LR
  classDef hot fill:#f96,stroke:#333,stroke-width:4px
  A[Start]:::hot --> B[End]
  style B fill:#9f6
```

## Strict security: click and links

```mermaid
flowchart LR
  A[Docs] --> B[Site]
  click A "https://example.com" "Open docs"
```

## Long labels wrap

```mermaid
flowchart TD
  A["This is a deliberately long label that should wrap across several lines in the rendered flowchart node"] --> B["Another long label, with commas, colons: and parentheses (like this) for wrapping"]
```

## Frontmatter theme and config

```mermaid
---
config:
  theme: dark
  flowchart:
    curve: basis
---
flowchart LR
  A --> B --> C
```

## Sequence with notes and loops

```mermaid
sequenceDiagram
  participant U as User
  participant S as Server
  loop Every minute
    U->>S: ping
    S-->>U: pong
  end
  Note right of S: Logs written
```

## Gantt with sections and milestones

```mermaid
gantt
  title Launch plan
  dateFormat YYYY-MM-DD
  section Build
  Design :done, d1, 2026-10-01, 5d
  Implement :active, i1, after d1, 10d
  section Ship
  Release :milestone, m1, after i1, 0d
```

## Pie with percentages

```mermaid
pie showData
  title Time spent
  "Code" : 55.5
  "Review" : 25
  "Meetings" : 19.5
```
