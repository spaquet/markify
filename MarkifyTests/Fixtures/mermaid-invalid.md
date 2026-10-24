# Invalid Mermaid

Each block should fail with a message, not render.

```mermaid
flowchart LR
  A -->
```

```mermaid
notARealDiagram
  A --> B
```
