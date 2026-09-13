;;; ecss-file.el --- File format helpers for ECSS -*- lexical-binding: t; -*-

;;; Commentary:
;; A `.ecss' file is one quoted, unevaluated Elisp list of rules:
;; ((".card" :color "red") ("& > .title" :font-weight bold))
;; Parsing is deliberately independent of Ebox; consumers mount the returned
;; rules into their own stylesheet and schema.

;;; Code:

(require 'ecss-cascade)
(require 'elisp-mode)
(defvar read-eval)

(defun ecss-file-read (file)
  "Read and validate the rule list stored in FILE."
  (unless (file-readable-p file)
    (user-error "ECSS file is not readable: %s" file))
  (with-temp-buffer
    (set-syntax-table emacs-lisp-mode-syntax-table)
    (insert-file-contents file)
    (let* ((read-eval nil)
           (form (read (current-buffer))))
      (forward-comment (point-max))
      (unless (eobp)
        (user-error "ECSS file must contain one expression: %s" file))
      (unless (and (consp form) (eq (car form) 'quote)
                   (consp (cdr form)) (null (cddr form)))
        (user-error "ECSS file must contain one quoted rule list: %s" file))
      (let ((value (cadr form)))
      (unless (proper-list-p value)
        (user-error "ECSS file must contain a rule list: %s" file))
      (mapcar (lambda (rule)
                (unless (and (proper-list-p rule) (stringp (car rule))
                             (zerop (% (length (cdr rule)) 2)))
                  (user-error "Invalid ECSS rule in %s: %S" file rule))
                (ecss-selector-parse (car rule))
                rule)
              value)))))

(defun ecss-file-load-into (file stylesheet schemas &optional origin)
  "Load FILE rules into STYLESHEET using SCHEMAS and ORIGIN."
  (let ((rules (ecss-file-read file))
        (validated (ecss-stylesheet-create)))
    ;; Validate every declaration before changing the caller's sheet.
    (dolist (rule rules)
      (ecss-stylesheet-add-rule validated schemas (car rule) (cdr rule)
                                :origin (or origin 'author)))
    (dolist (rule rules stylesheet)
      (ecss-stylesheet-add-rule stylesheet schemas (car rule) (cdr rule)
                                :origin (or origin 'author)))))

(provide 'ecss-file)
;;; ecss-file.el ends here
