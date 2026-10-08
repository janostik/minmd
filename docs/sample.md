---
title: minmd sample
tags: [markdown, solarized]
---

# minmd

An **extremely minimal** Markdown viewer — *no editing*, just reading. See [Code](#code) or [the repo](https://github.com/janostik/minmd).

## Text

Paragraphs, `inline code`, ~~strikethrough~~, <kbd>⌘</kbd> + <kbd>F</kbd>, and autolinks like https://example.com.

> Blockquotes look like this.
> They can span lines.

- Bullets
  - nested
- [x] Done task
- [ ] Open task

1. First
2. Second

## Code

```swift
struct Greeting {
    let name: String
    func say() -> String { "Hello, \(name)!" } // comment
}
```

```js
const answer = [1, 2, 3].map((n) => n * 14).at(-1); // 42
```

### Table

| Setting | Values               |
|---------|----------------------|
| Theme   | System · Light · Dark |
| Font    | JetBrains Mono, …    |

---

