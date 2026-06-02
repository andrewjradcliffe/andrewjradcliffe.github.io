/* On-demand MathJax (Q3.8/Q7.8): included only on pages with #+MATH: t.
   Configures, then loads the self-hosted CHTML bundle. No CDN. */
window.MathJax = {
  tex: { tags: "ams", tagSide: "right", tagIndent: ".8em" },
  chtml: { scale: 1.0, displayAlign: "center", displayIndent: "0em" },
  options: { enableMenu: false },
  startup: { typeset: true }
};
(function () {
  var s = document.createElement("script");
  s.src = "/js/mathjax/tex-mml-chtml.js";
  s.async = true;
  document.head.appendChild(s);
})();
