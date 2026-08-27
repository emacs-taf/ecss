;;; ecss-schema-tests.el --- Immutable schema composition tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Geekinney
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Code:

(require 'ert)
(require 'ecss)

(defun ecss-schema-test--definition (id &rest options)
  "Return a complete schema definition for ID extended by OPTIONS."
  (let ((definition (list :id id :initial nil :impacts '(paint))))
    (while options
      (setq definition (plist-put definition (pop options) (pop options))))
    definition))

(defun ecss-schema-test--package (id definitions)
  "Return immutable package ID built from DEFINITIONS."
  (ecss-schema-package-create id definitions))

(ert-deftest ecss-schema-package-validates-identity-and-definitions ()
  "Package and property identities have one strict grammar."
  (dolist (id '(nil :app "app" 4))
    (should-error
     (ecss-schema-package-create id nil)
     :type 'ecss-invalid-property-schema))
  (dolist (definition
           '((:id plain :impacts (paint))
             (:id app/color :impacts nil)
             (:id app/color :impacts (paint paint))
             (:id app/color :impacts (paint) :aliases (:tone :tone))
             (:id app/color :impacts (paint) :projections (tp tp))))
    (should-error
     (ecss-schema-package-create 'app (list definition))
     :type 'ecss-invalid-property-schema))
  (dolist
      (definitions
       '(((:id app/color :impacts (paint) :aliases (:tone))
          (:id app/gap :impacts (geometry) :aliases (:tone)))
         ((:id app/color :impacts (paint) :aliases (app/gap))
          (:id app/gap :impacts (geometry)))
         ((:id app/color :impacts (paint))
          (:id app/gap :impacts (geometry) :aliases (app/color)))))
    (should-error
     (ecss-schema-package-create 'app definitions)
     :type 'ecss-invalid-property-schema)))

(ert-deftest ecss-schema-package-copies-all-caller-owned-input ()
  "Package creation snapshots mutable schema input exactly once."
  (let* ((initial (vector (copy-sequence "red")))
         (aliases (list :tone))
         (impacts (list 'paint))
         (projections (list 'tp))
         (metadata-table
          (let ((table (make-hash-table :test #'eq)))
            (puthash 'role 'label table)
            table))
         (metadata (list :contexts (list 'text) :index metadata-table))
         (definition
          (list :id 'app/color :initial initial :aliases aliases
                :impacts impacts :projections projections :metadata metadata))
         (package (ecss-schema-package-create 'app (list definition)))
         (schemas (ecss-schema-set-compose package)))
    (aset (aref initial 0) 0 ?X)
    (setcar aliases :damaged)
    (setcar impacts 'geometry)
    (setcar projections 'layout)
    (setcar (plist-get metadata :contexts) 'box)
    (puthash 'role 'damaged metadata-table)
    (let ((property (ecss-schema-set-property schemas 'app/color)))
      (should (equal ["red"] (ecss-property-schema-initial property)))
      (should (equal '(:tone) (ecss-property-schema-aliases property)))
      (should (equal '(paint) (ecss-property-schema-impacts property)))
      (should (equal '(tp) (ecss-property-schema-projections property)))
      (let ((stored (ecss-property-schema-metadata property)))
        (should (equal '(text) (plist-get stored :contexts)))
        (should (eq 'label (gethash 'role (plist-get stored :index))))))
    (let ((canonical-metadata
           (ecss-schema-set-property-metadata schemas 'app/color))
          (alias-metadata
           (ecss-schema-set-property-metadata schemas :tone)))
      (should (equal (plist-get canonical-metadata :contexts)
                     (plist-get alias-metadata :contexts)))
      (should (eq (gethash 'role (plist-get canonical-metadata :index))
                  (gethash 'role (plist-get alias-metadata :index))))
      (setcar (plist-get canonical-metadata :contexts) 'damaged)
      (puthash 'role 'damaged (plist-get canonical-metadata :index))
      (let ((stored
             (ecss-schema-set-property-metadata schemas 'app/color)))
        (should (equal '(text) (plist-get stored :contexts)))
        (should (eq 'label (gethash 'role (plist-get stored :index))))))))

(ert-deftest ecss-schema-set-compose-rejects-complete-collision-matrix ()
  "Composition rejects package, canonical, and alias collisions atomically."
  (let* ((left
          (ecss-schema-test--package
           'left (list (ecss-schema-test--definition
                        'left/color :aliases '(shared/tone)))))
         (same-canonical
          (ecss-schema-test--package
           'right (list (ecss-schema-test--definition 'left/color))))
         (canonical-over-alias
          (ecss-schema-test--package
           'right (list (ecss-schema-test--definition 'shared/tone))))
         (alias-over-canonical
          (ecss-schema-test--package
           'right (list (ecss-schema-test--definition
                         'right/color :aliases '(left/color)))))
         (same-alias
          (ecss-schema-test--package
           'right (list (ecss-schema-test--definition
                         'right/color :aliases '(shared/tone))))))
    (should-error (ecss-schema-set-compose left left)
                  :type 'ecss-invalid-property-schema)
    (dolist (right (list same-canonical canonical-over-alias
                         alias-over-canonical same-alias))
      (should-error (ecss-schema-set-compose left right)
                    :type 'ecss-invalid-property-schema)
      (should (equal '(left/color)
                     (ecss-schema-set-property-ids
                      (ecss-schema-set-compose left))))
      (should (= 1 (length (ecss-schema-package-property-ids right)))))))

(ert-deftest ecss-schema-set-exposes-immutable-composition-index ()
  "Composed package order, canonical lookup, and schemas are deterministic."
  (let* ((app
          (ecss-schema-test--package
           'app (list (ecss-schema-test--definition
                       'app/color :aliases '(:tone)))))
         (ui
          (ecss-schema-test--package
           'ui (list (ecss-schema-test--definition 'ui/gap))))
         (schemas (ecss-schema-set-compose app ui))
         (ids (ecss-schema-set-property-ids schemas))
         (packages (ecss-schema-set-package-ids schemas))
         (property (ecss-schema-set-property schemas :tone)))
    (should (eq 'app (ecss-schema-package-id app)))
    (should (equal '(app/color) (ecss-schema-package-property-ids app)))
    (should (equal '(app ui) packages))
    (should (equal '(app/color ui/gap) ids))
    (should (eq 'app/color (ecss-schema-set-canonical-id schemas :tone)))
    (should (eq 'app/color (ecss-property-schema-id property)))
    (should (eq 'app (ecss-property-schema-owner property)))
    (setcar ids 'damaged)
    (setcar packages 'damaged)
    (setf (ecss-property-schema-owner property) 'damaged)
    (should (equal '(app ui) (ecss-schema-set-package-ids schemas)))
    (should (equal '(app/color ui/gap)
                   (ecss-schema-set-property-ids schemas)))
    (should (eq 'app
                (ecss-property-schema-owner
                 (ecss-schema-set-property schemas 'app/color))))))

(ert-deftest ecss-schema-aliases-disappear-before-cascade ()
  "Alias declarations normalize to canonical property identifiers."
  (let* ((package
          (ecss-schema-test--package
           'app
           (list (ecss-schema-test--definition
                  'app/color :initial "black" :aliases '(:tone)
                  :validator #'stringp))))
         (schemas (ecss-schema-set-compose package))
         (expanded (ecss-expand-declarations schemas '(:tone "red")))
         (style (ecss-compute-style
                 schemas (ecss-subject-create :type "box")
                 :declarations '(:tone "red") :provenance t)))
    (should (equal '(app/color "red") expanded))
    (should (equal '(app/color "red")
                   (ecss-computed-style-values style)))
    (should (equal "red" (ecss-computed-style-value style :tone)))
    (should (ecss-property-equal-p schemas :tone "red" "red"))
    (dolist (declarations
             '((:tone "red" app/color "blue")
               (:tone "red" :tone "blue")))
      (should-error
       (ecss-expand-declarations schemas declarations)
       :type 'ecss-invalid-declaration))))

(ert-deftest ecss-schema-shorthand-conflicts-with-owned-longhand ()
  "One declaration source cannot produce the same canonical output twice."
  (let* ((package
          (ecss-schema-test--package
           'app
           (list
            (ecss-schema-test--definition 'app/top)
            (ecss-schema-test--definition
             'app/padding
             :shorthand (lambda (value) (list 'app/top value))))))
         (schemas (ecss-schema-set-compose package)))
    (should-error
     (ecss-expand-declarations
      schemas '(app/padding 1 app/top 2))
     :type 'ecss-invalid-declaration)
    (should (equal '(app/top 2)
                   (ecss-merge-declarations
                    schemas '(app/padding 1) '(app/top 2))))))

(ert-deftest ecss-computed-property-fact-shares-value-and-multi-impact ()
  "One typed fact carries value, provenance, and every declared impact."
  (let* ((metadata (list :contexts '(text box)))
         (package
          (ecss-schema-test--package
           'app
           (list (ecss-schema-test--definition
                  'app/font :initial nil :impacts '(geometry paint)
                  :projections '(measure tp) :metadata metadata))))
         (schemas (ecss-schema-set-compose package))
         (value (list :family "Mono"))
         (style (ecss-compute-style
                 schemas (ecss-subject-create :type "text")
                 :declarations (list 'app/font value) :provenance t))
         (fact (ecss-computed-style-property-fact style 'app/font))
         (original-provenance
          (copy-tree (ecss-computed-property-fact-provenance fact))))
    (should (ecss-computed-property-fact-p fact))
    (should (equal (ecss-computed-property-fact-value fact)
                   (ecss-computed-style-value style 'app/font)))
    (should (equal '(geometry paint)
                   (ecss-computed-property-fact-impacts fact)))
    (should (equal '(measure tp)
                   (ecss-computed-property-fact-projections fact)))
    (should (eq 'app (ecss-computed-property-fact-owner fact)))
    (should (plist-get (ecss-computed-property-fact-provenance fact) :source))
    (should (equal (ecss-computed-property-fact-metadata fact)
                   (ecss-schema-set-property-metadata schemas 'app/font)))
    (let* ((fact-value (ecss-computed-property-fact-value fact))
           (geometry-value fact-value)
           (paint-value fact-value)
           (impacts (ecss-computed-property-fact-impacts fact))
          (projections (ecss-computed-property-fact-projections fact))
          (provenance (ecss-computed-property-fact-provenance fact))
          (fact-metadata (ecss-computed-property-fact-metadata fact)))
      (setcar fact-value :damaged-value)
      (setcar impacts 'damaged-impact)
      (setcar projections 'damaged-projection)
      (setcar provenance :damaged)
      (setcar (plist-get fact-metadata :contexts) 'damaged-context)
      (let ((fresh (ecss-computed-style-property-fact style 'app/font)))
        (should (eq geometry-value paint-value))
        (should (equal '(:family "Mono")
                       (ecss-computed-property-fact-value fresh)))
        (should (equal '(:family "Mono")
                       (ecss-computed-style-value style 'app/font)))
        (should (equal '(geometry paint)
                       (ecss-computed-property-fact-impacts fresh)))
        (should (equal '(measure tp)
                       (ecss-computed-property-fact-projections fresh)))
        (should (plist-get
                 (ecss-computed-property-fact-provenance fresh) :source))
        (should (equal '(text box)
                       (plist-get
                        (ecss-computed-property-fact-metadata fresh)
                        :contexts)))))
    (let* ((replacement (list :family "Serif"))
           (copy (ecss-computed-style-copy-with-values
                  style (list 'app/font replacement)))
           (copy-fact
            (ecss-computed-style-property-fact copy 'app/font)))
      (should (equal replacement
                     (ecss-computed-style-value copy 'app/font)))
      (should (equal (ecss-computed-property-fact-value copy-fact)
                     (ecss-computed-style-value copy 'app/font)))
      (should (equal original-provenance
                     (ecss-computed-property-fact-provenance copy-fact)))
      (should (equal '(geometry paint)
                     (ecss-computed-property-fact-impacts copy-fact))))))

(provide 'ecss-schema-tests)

;;; ecss-schema-tests.el ends here
