---
title: Editor fixture
tags: [fixture, editor]
date: 2026-09-26
---
# ATX heading

Setext heading
--------------

Plain ***both*** and _under_ and **a *b* c** and ~~struck~~ text.
Escaped \*not italic\* and snake_case_name stay plain.
Code `a*b*c | d` and [a link](other-note.md) and an ![inline](assets/tiny%20pic.png) image.

![Block image](assets/My%20pic.png)

![Remote](https://example.com/pic.png)

- bullet one
- bullet two
  - nested bullet
- [ ] open task
- [x] done task
  - [ ] nested task

3. three
4. four
lazy continuation line

| Name | Code |
| --- | --- |
| pipe | `a|b` |
| plain | text |

```swift
let x = 1
```

~~~
tilde fence
~~~

    indented code

$$
\frac{1}{2}
$$

Inline $x^2$ math.

> [!NOTE]
> Callout body.

> Plain quote.

Footnote ref[^1] here.

<div>html block</div>

---

[^1]: The footnote text.
