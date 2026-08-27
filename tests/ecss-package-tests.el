;;; ecss-package-tests.el --- Package boundary tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Geekinney
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Code:

(require 'ert)
(require 'package)
(require 'ecss)

(defconst ecss-package-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Absolute ecss repository root used by package tests.")

(defun ecss-package-test--source (file)
  "Return FILE contents below the repository root."
  (with-temp-buffer
    (insert-file-contents (expand-file-name file ecss-package-test--root))
    (buffer-string)))

(ert-deftest ecss-package-test-facade-loads-public-features-only ()
  (should (featurep 'ecss))
  (should (featurep 'ecss-selector))
  (should (featurep 'ecss-cascade))
  (should-not (featurep 'tp))
  (should-not (featurep 'ebox)))

(ert-deftest ecss-package-test-production-has-no-tp-or-ebox-dependency ()
  (dolist (file '("ecss.el" "ecss-selector.el" "ecss-cascade.el"))
    (let ((source (ecss-package-test--source file)))
      (should-not (string-match-p "(require[ \t\n]+['\"]tp" source))
      (should-not (string-match-p "(require[ \t\n]+['\"]ebox" source))
      (should-not (string-match-p "\\_<tp[-/]" source))
      (should-not (string-match-p "\\_<ebox[-/]" source)))))

(ert-deftest ecss-package-test-main-metadata-is-installable ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "ecss.el" ecss-package-test--root))
    (let ((description (package-buffer-info)))
      (should (equal (package-desc-name description) 'ecss))
      (should (version-list-<= '(28 1)
                               (cadr (assq 'emacs
                                           (package-desc-reqs description)))))
      (should (equal (package-version-join
                      (package-desc-version description))
                     "0.1.0")))))

(ert-deftest ecss-package-test-independent-schema-and-stylesheet-state ()
  (let ((left-schemas
         (ecss-schema-set-compose
          (ecss-schema-package-create
           'left '((:id left/color :initial "left" :impacts (paint))))))
        (right-schemas
         (ecss-schema-set-compose
          (ecss-schema-package-create
           'right '((:id right/color :initial "right" :impacts (paint))))))
        (left-sheet (ecss-stylesheet-create))
        (right-sheet (ecss-stylesheet-create)))
    (ecss-stylesheet-add-rule
     left-sheet left-schemas "*" '(left/color "changed"))
    (should (null (ecss-stylesheet-rules right-sheet)))
    (should (null (ecss-schema-set-property right-schemas 'left/color)))
    (should (equal (ecss-computed-style-value
                    (ecss-compute-style
                     right-schemas (ecss-subject-create :type "node")
                     :stylesheet right-sheet)
                    'right/color)
                   "right"))))

(provide 'ecss-package-tests)
;;; ecss-package-tests.el ends here
