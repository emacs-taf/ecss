;;; ecss-file-tests.el --- Public API acceptance -*- lexical-binding: t; -*-

;;; Commentary:
;; Test supported package inputs, outputs, errors and lifecycle.
;; Internal implementation details are outside this contract.

;;; Code:
(require 'cl-lib)
(require 'ert)
(require 'ecss)

(ert-deftest ecss-file-reads-one-rule-list ()
  (let ((file (make-temp-file "ecss-file-" nil ".ecss")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "'((\".card\" :color \"red\"))"))
          (should (equal (ecss-file-read file)
                         '((".card" :color "red")))))
      (delete-file file))))

(ert-deftest ecss-file-rejects-trailing-expression ()
  (let ((file (make-temp-file "ecss-file-" nil ".ecss")))
    (unwind-protect
        (progn
          (with-temp-file file (insert "nil"))
          (should-error (ecss-file-read file) :type 'user-error))
      (delete-file file))))

(provide 'ecss-file-tests)
;;; ecss-file-tests.el ends here
