;;; publish.el --- Build "the Zone" with org-publish -*- lexical-binding: t; -*-
;;
;; Usage:  emacs --batch -l site/publish.el -f org-publish-all
;;
;; main is source-only; this builds the site into ./public/.
;; See notes/spec.org (Part 0 Sub-spec C, Part III) for the design.

(require 'ox-publish)
(require 'ox-html)

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
  '(("projects" . "projects")
    ("writing"  . "writing")
    ("blog"     . "blog")
    ("about"    . "about")
    ("uses"     . "uses"))
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
          (if (string= name slug)
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

;;;; Project definition -------------------------------------------------------
(setq org-publish-project-alist
      `(("zone-pages"
         :base-directory ,(zone-path "src/")
         :base-extension "org"
         :publishing-directory ,zone-publish-dir
         :recursive t
         :publishing-function org-html-publish-to-html
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
         :base-extension "js"
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
