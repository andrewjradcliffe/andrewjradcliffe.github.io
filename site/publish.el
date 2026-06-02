;;; publish.el --- Build "the Zone" with org-publish -*- lexical-binding: t; -*-
;;
;; Usage:  emacs --batch -l site/publish.el -f org-publish-all
;;
;; main is source-only; this builds the site into ./public/.
;; See notes/spec.org (Part 0 Sub-spec C, Part III) for the design.

(require 'ox-publish)
(require 'ox-html)

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
      ;; Preamble/postamble are filled in Stage 1c; empty for now.
      org-html-preamble nil
      org-html-postamble nil)

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
