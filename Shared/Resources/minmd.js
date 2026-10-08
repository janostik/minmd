(() => {
  "use strict";

  const content = document.getElementById("content");
  const escapeHTML = (s) =>
    s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

  marked.use({ gfm: true });

  // GitHub-style heading anchors so in-document links like [x](#some-heading) work.
  function addHeadingIds() {
    const seen = new Map();
    for (const h of content.querySelectorAll("h1, h2, h3, h4, h5, h6")) {
      if (h.id) continue;
      const base = h.textContent.trim().toLowerCase()
        .replace(/[^\p{L}\p{N}\s_-]/gu, "")
        .replace(/\s/g, "-");
      const n = seen.get(base) ?? 0;
      seen.set(base, n + 1);
      h.id = n ? `${base}-${n}` : base;
    }
  }

  function highlight() {
    for (const el of content.querySelectorAll("pre code")) {
      const lang = [...el.classList].find((c) => c.startsWith("language-"))?.slice(9);
      if (lang && hljs.getLanguage(lang)) hljs.highlightElement(el);
    }
  }

  function render(markdown) {
    let front = "";
    const match = markdown.match(/^---\r?\n([\s\S]*?)\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/);
    if (match) {
      front = `<pre class="frontmatter"><code class="language-yaml">${escapeHTML(match[1])}</code></pre>`;
      markdown = markdown.slice(match[0].length);
    }
    content.innerHTML = front + marked.parse(markdown);
    addHeadingIds();
    highlight();
  }

  function setFont(stack) {
    document.documentElement.style.setProperty("--font-body", stack);
  }

  // In-page anchors: scroll instead of navigating (the page's base URL is the file's folder).
  document.addEventListener("click", (event) => {
    const link = event.target.closest('a[href^="#"]');
    if (!link) return;
    event.preventDefault();
    const id = decodeURIComponent(link.getAttribute("href").slice(1));
    document.getElementById(id)?.scrollIntoView({ behavior: "smooth" });
  });

  // Minimal find: ⌘F opens, Enter / ⌘G next, ⇧ for previous, Esc closes.
  function installFindBar() {
    const bar = document.createElement("div");
    bar.id = "find";
    bar.innerHTML = '<span>/</span><input type="search" spellcheck="false" placeholder="Find">';
    document.body.append(bar);
    const input = bar.querySelector("input");

    const find = (backwards) => {
      const query = input.value;
      if (!query) return bar.classList.remove("miss");
      // window.find moves the selection, so search from the input's perspective each time.
      const found = window.find(query, false, backwards, true, false, false, false);
      bar.classList.toggle("miss", !found);
      input.focus({ preventScroll: true });
    };

    const open = () => {
      bar.classList.add("open");
      const selected = String(window.getSelection() ?? "").trim();
      if (selected && !selected.includes("\n")) input.value = selected;
      input.select();
      input.focus();
    };

    const close = () => {
      bar.classList.remove("open", "miss");
      input.blur();
    };

    document.addEventListener("keydown", (event) => {
      const key = event.key.toLowerCase();
      if (event.metaKey && key === "f") { event.preventDefault(); open(); }
      else if (event.metaKey && key === "g") { event.preventDefault(); bar.classList.add("open"); find(event.shiftKey); }
      else if (key === "escape" && bar.classList.contains("open")) { event.preventDefault(); close(); }
    });

    input.addEventListener("keydown", (event) => {
      if (event.key === "Enter") { event.preventDefault(); find(event.shiftKey); }
    });
    input.addEventListener("input", () => {
      window.getSelection()?.removeAllRanges();
      find(false);
    });
  }

  window.minmd = { render, setFont };

  const initial = window.__MINMD__ ?? { markdown: "" };
  if (initial.findBar) installFindBar();
  render(initial.markdown);
})();
