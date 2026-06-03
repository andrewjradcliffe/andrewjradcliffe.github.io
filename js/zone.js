/* the Zone — progressive enhancement (Q10.3/10.4/4.1).
   The site is fully usable without this file. It adds:
     - a persisted dark/Sepia theme toggle
     - "/" fuzzy jump to a section (the minibuffer)
     - j/k scroll, gg/G top-bottom, "?" help overlay
   Nothing here is required to read or navigate the site. */
(function () {
  "use strict";
  var root = document.documentElement;
  root.classList.remove("no-js");

  /* ---- Theme toggle ------------------------------------------------- */
  var THEMES = ["dark", "sepia"];
  function currentTheme() {
    return root.getAttribute("data-theme") ||
      (matchMedia("(prefers-color-scheme: light)").matches ? "sepia" : "dark");
  }
  // Pin the effective theme as an explicit attribute on load, so the first
  // toggle click always changes it visibly (no dead first click).
  var stored = null;
  try { stored = localStorage.getItem("zone-theme"); } catch (e) {}
  root.setAttribute("data-theme", stored || currentTheme());
  function setTheme(t) {
    root.setAttribute("data-theme", t);
    try { localStorage.setItem("zone-theme", t); } catch (e) {}
    var b = document.querySelector(".theme-toggle");
    if (b) b.textContent = t === "sepia" ? "theme: sepia" : "theme: dark";
  }
  // Inject the toggle into the modeline footer, if present.
  var modeline = document.querySelector(".modeline");
  if (modeline) {
    var btn = document.createElement("button");
    btn.className = "theme-toggle";
    btn.type = "button";
    btn.setAttribute("aria-label", "Toggle color theme");
    btn.textContent = currentTheme() === "sepia" ? "theme: sepia" : "theme: dark";
    btn.addEventListener("click", function () {
      var i = THEMES.indexOf(currentTheme());
      setTheme(THEMES[(i + 1) % THEMES.length]);
    });
    modeline.appendChild(btn);
  }

  /* ---- Minibuffer: "/" fuzzy jump ----------------------------------- */
  var SECTIONS = [
    ["projects", "/projects/"], ["writing", "/writing/"],
    ["blog", "/blog/"], ["about", "/about/"], ["tikal", "/tikal/"],
    ["home", "/"]
  ];
  var mb, mbInput, mbList, mbOpen = false;
  function buildMinibuffer() {
    mb = document.createElement("div");
    mb.className = "minibuffer"; mb.hidden = true;
    mb.setAttribute("role", "dialog");
    mb.setAttribute("aria-label", "Jump to section");
    mb.innerHTML =
      '<div class="mb-box"><input class="mb-input" type="text" ' +
      'placeholder="jump to… (Esc to close)" aria-label="Jump to section" />' +
      '<ul class="mb-list"></ul></div>';
    document.body.appendChild(mb);
    mbInput = mb.querySelector(".mb-input");
    mbList = mb.querySelector(".mb-list");
    mbInput.addEventListener("input", renderList);
    mbInput.addEventListener("keydown", function (e) {
      if (e.key === "Enter") {
        var first = mbList.querySelector("a");
        if (first) location.href = first.getAttribute("href");
      } else if (e.key === "Escape") { closeMinibuffer(); }
    });
    mb.addEventListener("click", function (e) { if (e.target === mb) closeMinibuffer(); });
  }
  function renderList() {
    var q = mbInput.value.toLowerCase();
    var items = SECTIONS.filter(function (s) { return s[0].indexOf(q) !== -1; });
    mbList.innerHTML = items.map(function (s) {
      return '<li><a href="' + s[1] + '">' + s[0] + '</a></li>';
    }).join("");
  }
  function openMinibuffer() {
    if (!mb) buildMinibuffer();
    mbOpen = true; mb.hidden = false; mbInput.value = ""; renderList();
    mbInput.focus();
  }
  function closeMinibuffer() { if (mb) { mb.hidden = true; mbOpen = false; } }

  /* ---- Help overlay -------------------------------------------------- */
  var help;
  function toggleHelp() {
    if (!help) {
      help = document.createElement("div");
      help.className = "help-overlay"; help.hidden = true;
      help.setAttribute("role", "dialog");
      help.innerHTML =
        '<div class="help-box"><h2>keys</h2><dl>' +
        '<dt>/</dt><dd>jump to a section</dd>' +
        '<dt>j / k</dt><dd>scroll down / up</dd>' +
        '<dt>g g / G</dt><dd>top / bottom</dd>' +
        '<dt>?</dt><dd>this help</dd>' +
        '<dt>Esc</dt><dd>close</dd></dl>' +
        '<p class="help-hint">Esc to close</p></div>';
      document.body.appendChild(help);
      help.addEventListener("click", function () { help.hidden = true; });
    }
    help.hidden = !help.hidden;
  }

  /* ---- Key handling -------------------------------------------------- */
  var lastG = 0;
  function typing(e) {
    var t = e.target.tagName;
    return t === "INPUT" || t === "TEXTAREA" || e.target.isContentEditable;
  }
  document.addEventListener("keydown", function (e) {
    if (mbOpen) return;                 // minibuffer handles its own keys
    if (typing(e) || e.metaKey || e.ctrlKey || e.altKey) return;
    switch (e.key) {
      case "/": e.preventDefault(); openMinibuffer(); break;
      case "?": e.preventDefault(); toggleHelp(); break;
      case "j": scrollBy(0, 80); break;
      case "k": scrollBy(0, -80); break;
      case "G": scrollTo(0, document.body.scrollHeight); break;
      case "g":
        if (Date.now() - lastG < 400) scrollTo(0, 0);
        lastG = Date.now();
        break;
      case "Escape": closeMinibuffer(); if (help) help.hidden = true; break;
    }
  });
})();
