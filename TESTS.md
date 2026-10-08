| File                    | Contents                                                                | What it isolates                                   |
| ----------------------- | ----------------------------------------------------------------------- | -------------------------------------------------- |
| 01-gfm.md               | Tables, task lists, strikethrough, autolinks, nested lists, fenced code | Baseline GFM                                       |
| 02-gfm-html.md          | GFM plus <details>, <summary>, <kbd>, <sub>, <sup>, HTML tables         | Markdown/HTML boundaries                           |
| 03-gfm-math.md          | Inline and display math, math in table cells and lists, currency text   | Math delimiter handling                            |
| 04-gfm-mermaid.md       | Flowchart, sequence diagram, state diagram, ER diagram                  | Diagram rendering                                  |
| 05-all-features.md      | GFM + math + Mermaid + HTML                                             | Extension interactions                             |
| 06-long-all-features.md | Many distinct sections using all features                               | Large-document behavior                            |
| 07-incomplete-input.md  | Unclosed fences, partial formulas, unfinished HTML and diagrams         | Live-editing behavior                              |
| 08-html-security.md     | Separately labeled HTML sanitization cases                              | Security policy rather than formatting correctness |


https://github.com/microsoft/vscode-markdown-tm-grammar/tree/main/test/colorize-fixtures

https://github.com/mermaid-js/mermaid/blob/develop/README.md