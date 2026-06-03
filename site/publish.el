;;; publish.el --- Build "the Zone" with org-publish -*- lexical-binding: t; -*-
;;
;; Usage:  emacs --batch -l site/publish.el -f org-publish-all
;;
;; main is source-only; this builds the site into ./public/.
;; See notes/spec.org (Part 0 Sub-spec C, Part III) for the design.

(require 'ox-publish)
(require 'ox-html)
(require 'cl-lib)

;;;; Vendored build deps (pinned in site/lib/; no network at build) --------
(add-to-list 'load-path
             (expand-file-name "lib"
                               (file-name-directory
                                (or load-file-name buffer-file-name))))
(require 'htmlize)            ; needed for 'css fontified code output

;; Language major modes for code fontification. Built-ins always present;
;; vendored ones (julia) loaded if available; rust deferred (Sub-spec A).
(require 'julia-mode nil t)
(require 'cc-mode nil t)
(autoload 'python-mode "python" nil t)
(autoload 'sh-mode "sh-script" nil t)

;; Map Org src languages -> major modes so htmlize fontifies them.
(with-eval-after-load 'org-src
  (dolist (pair '(("julia" . julia)
                  ("python" . python)
                  ("sh" . sh) ("bash" . sh) ("shell" . sh)
                  ("C" . c) ("cpp" . c++)))
    (add-to-list 'org-src-lang-modes pair)))

;;;; Paths -------------------------------------------------------------------
;; Resolve the repo root from THIS file's location, so the build works
;; regardless of the current working directory (local make + CI).
(defconst zone-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Absolute path to the repository root (the parent of site/).")

(defun zone-path (rel) (expand-file-name rel zone-root))

(defconst zone-publish-dir (zone-path "public/"))
(defconst zone-site-url "https://andrewjradcliffe.github.io"
  "Absolute base URL, used for feed entry links (Q14.2).")
(defconst zone-author "Andrew Radcliffe")

;;;; HTML export settings -----------------------------------------------------
(setq make-backup-files nil
      org-export-with-toc nil
      org-export-with-section-numbers nil
      org-export-with-author nil
      org-export-with-timestamps nil
      org-html-doctype "html5"
      org-html-html5-fancy t
      org-html-validation-link nil
      org-html-htmlize-output-type 'css
      ;; We own the <head> via setupfile.org; no Org default styles/scripts.
      org-html-head-include-default-style nil
      org-html-head-include-scripts nil
      ;; Semantic landmark: content wrapper becomes <main id="content"> so
      ;; the skip-link target and the <main> landmark coincide (Q13.1).
      ;; preamble/postamble stay plain divs wrapping our own <nav>/<footer>.
      org-html-divs '((preamble  "div"  "preamble")
                      (content   "main" "content")
                      (postamble "div"  "postamble")))

;;;; Chrome: breadcrumb nav (preamble) + Emacs modeline (postamble) --------
;; No shell prompt (Q10.1). The modeline footer is the signature chrome
;; element (Q10.2). Both rendered as functions so page name + build date
;; are computed per page.

(defconst zone-sections
  ;; (display-label . url-path) — label may differ in case from the path.
  '(("projects" . "projects")
    ("writing"  . "writing")
    ("blog"     . "blog")
    ("about"    . "about")
    ("TIKaL"    . "tikal"))
  "Top-level sections for the breadcrumb nav, in order.")

(defun zone--page-slug (info)
  "Return a short page label (without .org) for the file in INFO."
  (let* ((in (plist-get info :input-file))
         (base (and in (file-name-base in)))
         (dir  (and in (file-name-nondirectory
                        (directory-file-name (file-name-directory in))))))
    (cond ((null in) "index")
          ;; blog posts live in src/blog/<slug>.org
          ((and (string= base "index") (not (string= dir "src"))) dir)
          (t base))))

(defun zone-preamble (info)
  "Plain-text breadcrumb nav (Q10.1). Home + the top sections."
  (let ((slug (zone--page-slug info)))
    (concat
     "<a class=\"skip-link\" href=\"#content\">Skip to content</a>\n"
     "<nav class=\"nav\" aria-label=\"Primary\">"
     "<a class=\"nav-home\" href=\"/\">Andrew Radcliffe</a>"
     "<span class=\"nav-sep\"> / </span>"
     (mapconcat
      (lambda (s)
        (let ((name (car s)) (path (cdr s)))
          ;; Match the current page on PATH (the slug), not the label,
          ;; so a label like "TIKaL" can differ in case from path "tikal".
          (if (string= path slug)
              (format "<span class=\"nav-here\" aria-current=\"page\">%s</span>" name)
            (format "<a href=\"/%s/\">%s</a>" path name))))
      zone-sections
      "<span class=\"nav-sep\"> · </span>")
     "</nav>")))

(defun zone-postamble (info)
  "Emacs-style modeline footer (Q10.2): page.org (Org) the-Zone rebuilt DATE."
  (let ((slug (zone--page-slug info))
        (date (format-time-string "%Y-%m-%d")))
    (format
     (concat "<footer class=\"modeline\" role=\"contentinfo\">"
             "<span class=\"ml-lead\">-UUU:----</span> "
             "<span class=\"ml-buf\">%s.org</span>"
             "<span class=\"ml-mode\">(Org)</span>"
             "<span class=\"ml-theme\">the-Zone</span>"
             "<span class=\"ml-date\">rebuilt %s</span>"
             "</footer>")
     slug date)))

(setq org-html-preamble  #'zone-preamble
      org-html-postamble #'zone-postamble)

;;;; On-demand math (Q3.8/Q7.8) ----------------------------------------------
;; A page opts in with `#+MATH: t'. We disable Org's own MathJax and inject
;; our self-hosted CHTML loader into <head> only on math pages. Keeps /,
;; /projects, etc. script-free.
(setq org-html-with-latex 'mathjax     ; emit \(..\) / \[..\] markup
      ;; ...but suppress Org's CDN MathJax <script>; we supply our own.
      org-html-mathjax-template "")

;; Register custom keywords as export options.
(require 'ox)
(dolist (opt '((:zone-math     "MATH"     nil nil t)
               (:zone-draft    "DRAFT"    nil nil t)
               (:zone-epigraph "EPIGRAPH" nil nil nil)
               (:zone-keywords "KEYWORDS" nil nil nil)))
  (add-to-list 'org-export-options-alist opt))

(defun zone--meta-escape (s)
  (let ((s (or s "")))
    (dolist (p '(("&" . "&amp;") ("\"" . "&quot;") ("<" . "&lt;") (">" . "&gt;")) s)
      (setq s (replace-regexp-in-string (regexp-quote (car p)) (cdr p) s t t)))))

(defun zone--inject-head (orig info)
  "Add per-page description + Open Graph meta, and the math loader when
#+MATH: t is set. Single point for all <head> extras (Q12.1/12.2/3.8)."
  (let* ((head (funcall orig info))
         (title (zone--meta-escape
                 (org-export-data (plist-get info :title) info)))
         (desc (zone--meta-escape
                (org-export-data (or (plist-get info :description) "") info)))
         (extra ""))
    (unless (string-empty-p desc)
      (setq extra (concat extra
                          (format "<meta name=\"description\" content=\"%s\" />\n" desc)
                          (format "<meta property=\"og:description\" content=\"%s\" />\n" desc))))
    (unless (string-empty-p title)
      (setq extra (concat extra
                          (format "<meta property=\"og:title\" content=\"%s\" />\n" title))))
    (when (plist-get info :zone-math)
      (setq extra (concat extra "<script defer src=\"/js/mathjax-loader.js\"></script>\n")))
    (concat head extra)))
(advice-add 'org-html--build-head :around #'zone--inject-head)

;; Root-relative links: Org turns [[/writing/]] into href="file:///writing/".
;; Strip the spurious file:// prefix from absolute-path links so they stay
;; site-root-relative (Q14.2). Applies to <a href> and src attributes.
(defun zone--fix-root-links (text backend _info)
  (if (org-export-derived-backend-p backend 'html)
      (replace-regexp-in-string
       "\\(href\\|src\\)=\"file://\\(/[^\"]*\\)\"" "\\1=\"\\2\"" text t)
    text))
(add-to-list 'org-export-filter-link-functions #'zone--fix-root-links)

;;;; Blog ---------------------------------------------------------------------
;; Posts live in src/blog/<slug>/index.org. A post with `#+DRAFT: t' is
;; excluded from the index, the feed, and prev/next (Q8.8). Metadata:
;; #+TITLE #+DATE #+KEYWORDS(tags) #+EPIGRAPH (Q8.4). The index is
;; reverse-chronological (Q8.5); the feed is Atom (Q12.3).

(defconst zone-blog-src (zone-path "src/blog/"))

(defun zone--read-keyword (file kw)
  "Return the value of #+KW: from FILE, or nil. KW without colon."
  (with-temp-buffer
    (insert-file-contents file nil 0 2000)
    (goto-char (point-min))
    (when (re-search-forward (format "^#\\+%s:[ \t]*\\(.*\\)$" kw) nil t)
      (let ((v (string-trim (match-string 1))))
        (unless (string-empty-p v) v)))))

(defun zone--post-files ()
  "All post source files src/blog/<slug>/index.org (NOT the blog index itself)."
  (when (file-directory-p zone-blog-src)
    (cl-remove-if
     (lambda (f)
       ;; exclude src/blog/index.org (the generated listing)
       (string= (expand-file-name f)
                (expand-file-name "index.org" zone-blog-src)))
     (directory-files-recursively zone-blog-src "\\`index\\.org\\'"))))

(defun zone--post-meta (file)
  "Plist of (:file :slug :title :date :tags :epigraph :draft) for FILE."
  (let* ((slug (file-name-nondirectory
                (directory-file-name (file-name-directory file))))
         (tags (zone--read-keyword file "KEYWORDS")))
    (list :file file
          :slug slug
          :title (or (zone--read-keyword file "TITLE") slug)
          :date  (or (zone--read-keyword file "DATE") "")
          :tags  (and tags (split-string tags "[ ,]+" t))
          :epigraph (zone--read-keyword file "EPIGRAPH")
          :draft (and (zone--read-keyword file "DRAFT") t))))

(defun zone-published-posts ()
  "Non-draft post metadata, newest first (Q8.5/Q8.8)."
  (sort (cl-remove-if (lambda (m) (plist-get m :draft))
                      (mapcar #'zone--post-meta (zone--post-files)))
        (lambda (a b) (string> (plist-get a :date) (plist-get b :date)))))

(defun zone--reading-time (file)
  "Rough reading time in minutes for FILE body (~200 wpm)."
  (with-temp-buffer
    (insert-file-contents file)
    (max 1 (round (/ (count-words (point-min) (point-max)) 200.0)))))

;; Is the current export a blog post? (input under src/blog/)
(defun zone--blog-post-p (info)
  (let ((in (plist-get info :input-file)))
    (and in (string-prefix-p zone-blog-src (expand-file-name in)))))

(defun zone--post-header (info)
  "Date · tags · reading-time line + optional epigraph, for a post top."
  (let* ((in (plist-get info :input-file))
         (date (org-export-data (plist-get info :date) info))
         (date (if (string-empty-p date)
                   (or (zone--read-keyword in "DATE") "") date))
         (tags (let ((k (zone--read-keyword in "KEYWORDS")))
                 (and k (split-string k "[ ,]+" t))))
         (mins (zone--reading-time in))
         (epi  (zone--read-keyword in "EPIGRAPH")))
    (concat
     "<p class=\"post-meta\">"
     (and (not (string-empty-p date)) (format "<time>%s</time>" date))
     (when tags
       (concat " · " (mapconcat (lambda (tg)
                                  (format "<span class=\"tag\">%s</span>" tg))
                                tags " ")))
     (format " · <span class=\"rt\">~%d min</span>" mins)
     "</p>"
     (when epi (format "<p class=\"epigraph\">%s</p>" epi)))))

(defun zone--post-footer (info)
  "Prev/next links + reply-by-email footer for a post (Q8.6/8.7)."
  (let* ((in (expand-file-name (plist-get info :input-file)))
         (posts (zone-published-posts))
         (slugs (mapcar (lambda (m) (plist-get m :slug)) posts))
         (this (file-name-nondirectory
                (directory-file-name (file-name-directory in))))
         (pos (cl-position this slugs :test #'string=))
         ;; posts are newest-first: "newer" = previous index, "older" = next
         (newer (and pos (> pos 0) (nth (1- pos) posts)))
         (older (and pos (nth (1+ pos) posts))))
    (concat
     "<nav class=\"post-nav\" aria-label=\"Adjacent posts\">"
     (if older
         (format "<a class=\"prev\" href=\"/blog/%s/\">← %s</a>"
                 (plist-get older :slug) (plist-get older :title))
       "<span></span>")
     (if newer
         (format "<a class=\"next\" href=\"/blog/%s/\">%s →</a>"
                 (plist-get newer :slug) (plist-get newer :title))
       "<span></span>")
     "</nav>"
     "<p class=\"reply\">Found a mistake or have a thought? "
     "<a href=\"/about/\">Reply by email</a> or open an issue.</p>")))

;; Compose the post chrome into the postamble (after the modeline base).
(defun zone-postamble-blog (orig info)
  "For posts, prepend the post footer to the modeline postamble."
  (if (zone--blog-post-p info)
      (concat (zone--post-footer info) (funcall orig info))
    (funcall orig info)))

;; Inject the post header (date/tags/rt/epigraph) right after the body opens.
(add-to-list 'org-export-filter-body-functions
             (lambda (body backend info)
               (if (and (org-export-derived-backend-p backend 'html)
                        (zone--blog-post-p info))
                   (concat (zone--post-header info) body)
                 body)))

;; Draft-aware publish: skip #+DRAFT posts entirely (Q8.8).
(defun zone-publish-to-html (plist filename pub-dir)
  "Like `org-html-publish-to-html', but skip #+DRAFT posts and give real
posts a `post-body' content class so serif prose applies (Q5.8)."
  (cond
   ((and (string-match-p "/blog/" filename)
         (zone--read-keyword filename "DRAFT"))
    (message "Skipping draft: %s" filename) nil)
   ((and (string-match-p "/blog/" filename)
         (not (string-suffix-p "blog/index.org" filename)))
    (let ((org-html-content-class "content post-body"))
      (org-html-publish-to-html plist filename pub-dir)))
   (t (org-html-publish-to-html plist filename pub-dir))))

;;;; Blog index (reverse-chron) + Atom feed -----------------------------------
(defun zone-build-blog-index (&rest _)
  "Generate src/blog/index.org listing published posts, newest first."
  (let ((posts (zone-published-posts)))
    (with-temp-file (expand-file-name "index.org" zone-blog-src)
      (insert "#+SETUPFILE: ../../site/setupfile.org\n")
      (insert "#+TITLE: Blog\n\n")
      (insert "Essays. Mostly technical, sometimes not.\n\n")
      (if (null posts)
          (insert "Nothing published yet.\n")
        (dolist (m posts)
          (insert (format "- =%s= [[/blog/%s/][%s]]\n"
                          (plist-get m :date)
                          (plist-get m :slug)
                          (plist-get m :title))))))))

(defun zone--atom-escape (s)
  (let ((s (or s "")))
    (dolist (p '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;")) s)
      (setq s (replace-regexp-in-string (regexp-quote (car p)) (cdr p) s t t)))))

(defun zone-build-feed (&rest _)
  "Write public/feed.xml (Atom) from published posts (Q12.3)."
  (let* ((posts (zone-published-posts))
         (updated (if posts (concat (plist-get (car posts) :date) "T00:00:00Z")
                    "1970-01-01T00:00:00Z"))
         (feed (expand-file-name "feed.xml" zone-publish-dir)))
    (make-directory zone-publish-dir t)
    (with-temp-file feed
      (insert "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
      (insert "<feed xmlns=\"http://www.w3.org/2005/Atom\">\n")
      (insert (format "  <title>%s</title>\n" zone-author))
      (insert (format "  <link href=\"%s/feed.xml\" rel=\"self\"/>\n" zone-site-url))
      (insert (format "  <link href=\"%s/\"/>\n" zone-site-url))
      (insert (format "  <id>%s/</id>\n" zone-site-url))
      (insert (format "  <updated>%s</updated>\n" updated))
      (insert (format "  <author><name>%s</name></author>\n" zone-author))
      (dolist (m posts)
        (let ((url (format "%s/blog/%s/" zone-site-url (plist-get m :slug))))
          (insert "  <entry>\n")
          (insert (format "    <title>%s</title>\n" (zone--atom-escape (plist-get m :title))))
          (insert (format "    <link href=\"%s\"/>\n" url))
          (insert (format "    <id>%s</id>\n" url))
          (insert (format "    <updated>%sT00:00:00Z</updated>\n" (plist-get m :date)))
          (dolist (tg (plist-get m :tags))
            (insert (format "    <category term=\"%s\"/>\n" (zone--atom-escape tg))))
          (insert "  </entry>\n")))
      (insert "</feed>\n"))
    (message "Wrote %s (%d entries)" feed (length posts))))

;; Blog postamble: posts get prev/next + reply footer above the modeline.
(advice-add 'zone-postamble :around #'zone-postamble-blog)

(defun zone-build-sitemap (&rest _)
  "Write public/sitemap.xml + robots.txt from published HTML (Q12.5)."
  (let* ((htmls (and (file-directory-p zone-publish-dir)
                     (directory-files-recursively zone-publish-dir "index\\.html\\'")))
         (sm (expand-file-name "sitemap.xml" zone-publish-dir)))
    (with-temp-file sm
      (insert "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
      (insert "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n")
      (dolist (h (sort htmls #'string<))
        (let* ((rel (file-relative-name h zone-publish-dir))
               (dir (file-name-directory rel))       ; nil for top-level index
               (url (format "%s/%s" zone-site-url (or dir ""))))
          (insert (format "  <url><loc>%s</loc></url>\n" url))))
      (insert "</urlset>\n"))
    (with-temp-file (expand-file-name "robots.txt" zone-publish-dir)
      (insert "User-agent: *\nAllow: /\n")
      (insert (format "Sitemap: %s/sitemap.xml\n" zone-site-url)))
    (message "Wrote sitemap.xml (%d urls) + robots.txt" (length htmls))))

(defun zone-copy-root-icons (&rest _)
  "Copy favicon.svg/.ico to the site root (browsers fetch /favicon.ico)."
  (dolist (f '("favicon.svg" "favicon.ico"))
    (let ((src (expand-file-name f (zone-path "img/")))
          (dst (expand-file-name f zone-publish-dir)))
      (when (file-exists-p src) (copy-file src dst t)))))

(defun zone-finish (&rest _)
  "Completion hook for zone-pages: icons, feed, sitemap + robots."
  (zone-copy-root-icons)
  (zone-build-feed)
  (zone-build-sitemap))

;;;; Project definition -------------------------------------------------------
(setq org-publish-project-alist
      `(("zone-pages"
         :base-directory ,(zone-path "src/")
         :base-extension "org"
         :publishing-directory ,zone-publish-dir
         :recursive t
         :publishing-function zone-publish-to-html   ; skips #+DRAFT posts
         :preparation-function zone-build-blog-index  ; (re)generate blog index
         :completion-function zone-finish             ; feed + sitemap + robots
         :with-toc nil
         :section-numbers nil)

        ;; Static asset trees: each top-level dir -> public/<same>/.
        ;; Explicit per-dir components avoid walking .git/, public/, notes/.
        ("zone-css"
         :base-directory ,(zone-path "css/")
         :base-extension "css"
         :publishing-directory ,(zone-path "public/css/")
         :publishing-function org-publish-attachment)

        ("zone-fonts"
         :base-directory ,(zone-path "fonts/")
         :base-extension "woff2\\|woff"
         :publishing-directory ,(zone-path "public/fonts/")
         :publishing-function org-publish-attachment)

        ("zone-js"
         :base-directory ,(zone-path "js/")
         :base-extension "js\\|woff2\\|woff\\|css"
         :recursive t                  ; include js/mathjax/ subtree
         :publishing-directory ,(zone-path "public/js/")
         :publishing-function org-publish-attachment)

        ("zone-img"
         :base-directory ,(zone-path "img/")
         :base-extension "png\\|jpg\\|jpeg\\|gif\\|svg\\|ico\\|pdf"
         :publishing-directory ,(zone-path "public/img/")
         :recursive t
         :publishing-function org-publish-attachment)

        ("zone"
         :components ("zone-pages" "zone-css" "zone-fonts" "zone-js" "zone-img"))))

(provide 'publish)
;;; publish.el ends here
