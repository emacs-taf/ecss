;;; ecss-cascade-tests.el --- Cascade tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Geekinney
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'ecss-cascade)

(defun ecss-cascade-test--schemas ()
  "Return the standard test schema set."
  (let ((schemas (ecss-schema-set-create)))
    (ecss-schema-set-define
     schemas 'app/color :initial "black" :inherits t
     :validator #'stringp)
    (ecss-schema-set-define
     schemas 'app/width :initial 0 :validator #'integerp)
    (ecss-schema-set-define schemas 'app/payload :initial nil :inherits t)
    (dolist (property '(app/padding-top app/padding-right
                        app/padding-bottom app/padding-left))
      (ecss-schema-set-define
       schemas property :initial 0 :validator #'integerp))
    (ecss-schema-set-define
     schemas 'app/padding
     :shorthand
     (lambda (value)
       (list 'app/padding-top value 'app/padding-right value
             'app/padding-bottom value 'app/padding-left value)))
    schemas))

(defun ecss-cascade-test--subject (&rest options)
  "Return a button subject using OPTIONS."
  (apply #'ecss-subject-create :type "button" options))

(defun ecss-cascade-test--value (style property)
  "Return PROPERTY from computed STYLE."
  (ecss-computed-style-value style property :absent))

(ert-deftest ecss-cascade-test-schema-registration-is-atomic ()
  (let ((schemas (ecss-schema-set-create)))
    (ecss-schema-set-define schemas 'app/width :initial 4 :validator #'integerp)
    (should-error
     (ecss-schema-set-define schemas 'app/width :initial "bad"
                             :validator #'integerp)
     :type 'ecss-invalid-property-schema)
    (should (= (ecss-property-schema-initial
                (ecss-schema-set-property schemas 'app/width))
               4))
    (should-error
     (ecss-schema-set-define schemas 'not-namespaced :initial 1)
     :type 'ecss-invalid-property-schema)
    (should (equal (ecss-schema-set-property-ids schemas) '(app/width)))))

(ert-deftest ecss-cascade-test-computed-defaults-are-not-renormalized ()
  (let ((schemas (ecss-schema-set-create))
        (subject (ecss-cascade-test--subject))
        (normalizations 0))
    (ecss-schema-set-define
     schemas 'app/value :initial 2 :inherits t
     :normalizer (lambda (value) (cl-incf normalizations) (* value 10))
     :validator #'integerp)
    (let* ((initial (ecss-compute-style schemas subject))
           (declared (ecss-compute-style
                      schemas subject :declarations '(app/value 3)))
           (inherited (ecss-compute-style
                       schemas subject :parent-style declared))
           (wide-initial
            (ecss-compute-style
             schemas subject :parent-style declared
             :declarations
             (list 'app/value (ecss-wide-value 'initial)))))
      (should (= (ecss-cascade-test--value initial 'app/value) 20))
      (should (= (ecss-cascade-test--value declared 'app/value) 30))
      (should (= (ecss-cascade-test--value inherited 'app/value) 30))
      (should (= (ecss-cascade-test--value wide-initial 'app/value) 20))
      (should (= normalizations 2)))))

(ert-deftest ecss-cascade-test-shorthand-expands-once-and-preserves-important ()
  (let* ((schemas (ecss-cascade-test--schemas))
         (expanded (ecss-expand-declarations
                    schemas (list 'app/padding (ecss-important 3)))))
    (should (equal (cl-loop for (property _value) on expanded by #'cddr
                            collect property)
                   '(app/padding-top app/padding-right
                     app/padding-bottom app/padding-left)))
    (cl-loop for (_property value) on expanded by #'cddr
             do (should (ecss--important-p value))
             do (should (= (ecss--important-value value) 3)))))

(ert-deftest ecss-cascade-test-shorthand-and-longhand-follow-declaration-order ()
  (let ((schemas (ecss-cascade-test--schemas))
        (subject (ecss-cascade-test--subject)))
    (should (= (ecss-cascade-test--value
                (ecss-compute-style
                 schemas subject
                 :declarations '(app/padding 1 app/padding-left 2))
                'app/padding-left)
               2))
    (should (= (ecss-cascade-test--value
                (ecss-compute-style
                 schemas subject
                 :declarations '(app/padding-left 2 app/padding 1))
                'app/padding-left)
               1))))

(ert-deftest ecss-cascade-test-rule-addition-is-atomic ()
  (let ((schemas (ecss-cascade-test--schemas))
        (stylesheet (ecss-stylesheet-create)))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".valid" '(app/color "blue") :layer 'base)
    (should-error
     (ecss-stylesheet-add-rule
      stylesheet schemas ".broken" '(unknown/value 1) :layer 'broken)
     :type 'ecss-invalid-declaration)
    (should (equal (ecss-stylesheet-layers stylesheet) '(base)))
    (should (= (length (ecss-stylesheet-rules stylesheet)) 1))))

(ert-deftest ecss-cascade-test-origin-importance-and-transition-order ()
  (let ((schemas (ecss-cascade-test--schemas))
        (stylesheet (ecss-stylesheet-create))
        (subject (ecss-cascade-test--subject :classes '("target"))))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "ua") :origin 'ua)
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "user") :origin 'user)
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "author") :origin 'author)
    (should (equal (ecss-cascade-test--value
                    (ecss-compute-style schemas subject :stylesheet stylesheet)
                    'app/color)
                   "author"))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target"
     (list 'app/color (ecss-important "author-important"))
     :origin 'author)
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target"
     (list 'app/color (ecss-important "user-important"))
     :origin 'user)
    (should (equal (ecss-cascade-test--value
                    (ecss-compute-style schemas subject :stylesheet stylesheet)
                    'app/color)
                   "user-important"))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "transition")
     :origin 'transition)
    (should (equal (ecss-cascade-test--value
                    (ecss-compute-style schemas subject :stylesheet stylesheet)
                    'app/color)
                   "transition"))))

(ert-deftest ecss-cascade-test-standard-origin-levels-are-complete ()
  (let ((schemas (ecss-cascade-test--schemas))
        (stylesheet (ecss-stylesheet-create))
        (subject (ecss-cascade-test--subject :classes '("target"))))
    (dolist (entry
             (list (list 'author "author")
                   (list 'animation "animation")
                   (list 'author (ecss-important "author-important"))
                   (list 'user (ecss-important "user-important"))
                   (list 'ua (ecss-important "ua-important"))))
      (ecss-stylesheet-add-rule
       stylesheet schemas ".target" (list 'app/color (cadr entry))
       :origin (car entry)))
    (should (equal (ecss-cascade-test--value
                    (ecss-compute-style schemas subject :stylesheet stylesheet)
                    'app/color)
                   "ua-important"))))

(ert-deftest ecss-cascade-test-layer-order-reverses-for-important ()
  (let ((schemas (ecss-cascade-test--schemas))
        (normal (ecss-stylesheet-create))
        (important (ecss-stylesheet-create))
        (subject (ecss-cascade-test--subject :classes '("target"))))
    (ecss-stylesheet-declare-layers normal '(base components))
    (ecss-stylesheet-add-rule
     normal schemas ".target" '(app/color "base") :layer 'base)
    (ecss-stylesheet-add-rule
     normal schemas ".target" '(app/color "components") :layer 'components)
    (ecss-stylesheet-add-rule normal schemas ".target" '(app/color "plain"))
    (should (equal (ecss-cascade-test--value
                    (ecss-compute-style schemas subject :stylesheet normal)
                    'app/color)
                   "plain"))
    (ecss-stylesheet-declare-layers important '(base components))
    (dolist (entry '((base "base") (components "components") (nil "plain")))
      (ecss-stylesheet-add-rule
       important schemas ".target"
       (list 'app/color (ecss-important (cadr entry)))
       :layer (car entry)))
    (should (equal (ecss-cascade-test--value
                    (ecss-compute-style schemas subject :stylesheet important)
                    'app/color)
                   "base"))
    (should (equal (ecss-cascade-test--value
                    (ecss-compute-style
                     schemas subject :stylesheet important
                     :declarations
                     (list 'app/color (ecss-important "inline")))
                    'app/color)
                   "inline"))))

(ert-deftest ecss-cascade-test-layer-order-is-independent-per-origin ()
  (let ((stylesheet (ecss-stylesheet-create)))
    (ecss-stylesheet-declare-layers stylesheet '(base components) 'author)
    (ecss-stylesheet-declare-layers stylesheet '(components base) 'user)
    (should (equal (ecss-stylesheet-layers stylesheet 'author)
                   '(base components)))
    (should (equal (ecss-stylesheet-layers stylesheet 'user)
                   '(components base)))))

(ert-deftest ecss-cascade-test-specificity-source-order-and-selector-list ()
  (let ((schemas (ecss-cascade-test--schemas))
        (stylesheet (ecss-stylesheet-create))
        (subject (ecss-cascade-test--subject
                  :id "actual" :classes '("target"))))
    (ecss-stylesheet-add-rule
     stylesheet schemas "#other, .target" '(app/color "first"))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "later"))
    (should (equal (ecss-cascade-test--value
                    (ecss-compute-style schemas subject :stylesheet stylesheet)
                    'app/color)
                   "later"))
    (ecss-stylesheet-add-rule
     stylesheet schemas "button#actual" '(app/color "id"))
    (should (equal (ecss-cascade-test--value
                    (ecss-compute-style schemas subject :stylesheet stylesheet)
                    'app/color)
                   "id"))))

(ert-deftest ecss-cascade-test-scope-proximity-follows-specificity ()
  (let* ((schemas (ecss-cascade-test--schemas))
         (stylesheet (ecss-stylesheet-create))
         (target (ecss-cascade-test--subject :classes '("target")))
         (inner (ecss-subject-create
                 :type "section" :classes '("inner")
                 :children (list target)))
         (_outer (ecss-subject-create
                  :type "main" :classes '("outer")
                  :children (list inner))))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "outer") :scope ".outer")
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "inner") :scope ".inner")
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "missing") :scope ".missing")
    (should (equal (ecss-cascade-test--value
                    (ecss-compute-style schemas target :stylesheet stylesheet)
                    'app/color)
                   "inner"))))

(ert-deftest ecss-cascade-test-inheritance-distinguishes-nil-from-absence ()
  (let* ((schemas (ecss-cascade-test--schemas))
         (subject (ecss-cascade-test--subject))
         (parent (ecss-compute-style
                  schemas subject
                  :declarations '(app/color "red" app/payload nil)))
         (child (ecss-compute-style schemas subject :parent-style parent))
         (initial (ecss-compute-style schemas subject)))
    (should (equal (ecss-cascade-test--value child 'app/color) "red"))
    (should (null (ecss-cascade-test--value child 'app/payload)))
    (should (ecss-computed-style-present-p child 'app/payload))
    (should-not (ecss-computed-style-present-p initial 'app/payload))))

(ert-deftest ecss-cascade-test-css-wide-values-use-cascade-not-symbol-reservation ()
  (let* ((schemas (ecss-cascade-test--schemas))
         (subject (ecss-cascade-test--subject :classes '("target")))
         (parent (ecss-compute-style
                  schemas subject :declarations '(app/color "parent")))
         (inherit (ecss-compute-style
                   schemas subject :parent-style parent
                   :declarations
                   (list 'app/color (ecss-wide-value 'inherit))))
         (initial (ecss-compute-style
                   schemas subject :parent-style parent
                   :declarations
                   (list 'app/color (ecss-wide-value 'initial)))))
    (should (equal (ecss-cascade-test--value inherit 'app/color) "parent"))
    (should (equal (ecss-cascade-test--value initial 'app/color) "black"))
    (should (equal (ecss-cascade-test--value
                    (ecss-compute-style
                     schemas subject :declarations '(app/payload inherit))
                    'app/payload)
                   'inherit))))

(ert-deftest ecss-cascade-test-revert-and-revert-layer-select-lower-candidates ()
  (let ((schemas (ecss-cascade-test--schemas))
        (stylesheet (ecss-stylesheet-create))
        (subject (ecss-cascade-test--subject :classes '("target"))))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "ua") :origin 'ua)
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "author") :origin 'author)
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target"
     (list 'app/color (ecss-wide-value 'revert)) :origin 'author)
    (should (equal (ecss-cascade-test--value
                    (ecss-compute-style schemas subject :stylesheet stylesheet)
                    'app/color)
                   "ua"))
    (ecss-stylesheet-clear stylesheet)
    (ecss-stylesheet-declare-layers stylesheet '(base components))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "base") :layer 'base)
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "components")
     :layer 'components)
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target"
     (list 'app/color (ecss-wide-value 'revert-layer)) :layer 'components)
    (should (equal (ecss-cascade-test--value
                    (ecss-compute-style schemas subject :stylesheet stylesheet)
                    'app/color)
                   "base"))))

(ert-deftest ecss-cascade-test-important-revert-removes-entire-origin ()
  (let ((schemas (ecss-cascade-test--schemas))
        (stylesheet (ecss-stylesheet-create))
        (subject (ecss-cascade-test--subject :classes '("target"))))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "user") :origin 'user)
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "author-normal")
     :origin 'author)
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target"
     (list 'app/color (ecss-important (ecss-wide-value 'revert)))
     :origin 'author)
    (should (equal (ecss-cascade-test--value
                    (ecss-compute-style schemas subject :stylesheet stylesheet)
                    'app/color)
                   "user"))))

(ert-deftest ecss-cascade-test-important-revert-layer-removes-entire-layer ()
  (let ((schemas (ecss-cascade-test--schemas))
        (stylesheet (ecss-stylesheet-create))
        (subject (ecss-cascade-test--subject :classes '("target"))))
    (ecss-stylesheet-declare-layers stylesheet '(base components))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "base") :layer 'base)
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "component-normal")
     :layer 'components)
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target"
     (list 'app/color (ecss-important (ecss-wide-value 'revert-layer)))
     :layer 'components)
    (should (equal (ecss-cascade-test--value
                    (ecss-compute-style schemas subject :stylesheet stylesheet)
                    'app/color)
                   "base"))))

(ert-deftest ecss-cascade-test-custom-property-revert-removes-entire-origin ()
  (let ((schemas (ecss-cascade-test--schemas))
        (stylesheet (ecss-stylesheet-create))
        (subject (ecss-cascade-test--subject :classes '("target"))))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(--theme 7) :origin 'user)
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(--theme 8) :origin 'author)
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target"
     (list '--theme (ecss-important (ecss-wide-value 'revert)))
     :origin 'author)
    (let ((style (ecss-compute-style
                  schemas subject :stylesheet stylesheet
                  :declarations (list 'app/width (ecss-var '--theme)))))
      (should (= (ecss-cascade-test--value style 'app/width) 7)))))

(ert-deftest ecss-cascade-test-custom-properties-resolve-nested-values ()
  (let* ((schemas (ecss-cascade-test--schemas))
         (subject (ecss-cascade-test--subject))
         (style (ecss-compute-style
                 schemas subject
                 :declarations
                 (list '--base 12 '--alias (ecss-var '--base)
                       'app/width (ecss-var '--alias)
                       'app/payload (list 'calc (ecss-var '--base))))))
    (should (= (ecss-cascade-test--value style 'app/width) 12))
    (should (equal (ecss-cascade-test--value style 'app/payload)
                   '(calc 12)))
    (should (equal (ecss-computed-style-custom-properties style)
                   '(--alias 12 --base 12)))))

(ert-deftest ecss-cascade-test-custom-properties-inherit-by-default ()
  (let* ((schemas (ecss-cascade-test--schemas))
         (subject (ecss-cascade-test--subject))
         (parent (ecss-compute-style
                  schemas subject :declarations '(--theme 17)))
         (child (ecss-compute-style
                 schemas subject :parent-style parent
                 :declarations (list 'app/width (ecss-var '--theme)))))
    (should (= (ecss-cascade-test--value child 'app/width) 17))
    (should (equal (ecss-computed-style-custom-properties child)
                   '(--theme 17)))))

(ert-deftest ecss-cascade-test-variable-cycle-uses-outer-fallback ()
  (let* ((schemas (ecss-cascade-test--schemas))
         (style (ecss-compute-style
                 schemas (ecss-cascade-test--subject)
                 :declarations
                 (list '--a (ecss-var '--b) '--b (ecss-var '--a)
                       'app/width (ecss-var '--a 9)))))
    (should (= (ecss-cascade-test--value style 'app/width) 9))
    (should (equal (ecss-computed-style-diagnostics style)
                   '((:type variable-cycle :path (--a --b --a)))))
    (should (null (ecss-computed-style-custom-properties style)))))

(ert-deftest ecss-cascade-test-parent-plist-is-snapshotted ()
  (let* ((schemas (ecss-cascade-test--schemas))
         (payload (list 'original))
         (parent (list 'app/payload payload))
         (style (ecss-compute-style
                 schemas (ecss-cascade-test--subject)
                 :parent-style parent)))
    (setcar payload 'damaged)
    (should (equal (ecss-cascade-test--value style 'app/payload)
                   '(original)))))

(ert-deftest ecss-cascade-test-invalid-winner-does-not-recascade ()
  (let ((schemas (ecss-cascade-test--schemas))
        (stylesheet (ecss-stylesheet-create))
        (subject (ecss-cascade-test--subject :classes '("target"))))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/width 10))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/width "invalid"))
    (let* ((style (ecss-compute-style
                   schemas subject :stylesheet stylesheet :provenance t))
           (facts (plist-get (ecss-computed-style-provenance style)
                             'app/width)))
      (should (= (ecss-cascade-test--value style 'app/width) 0))
      (should (eq (plist-get facts :valid) nil))
      (should (eq (plist-get facts :fallback) 'initial))
      (should-not (ecss-computed-style-present-p style 'app/width)))))

(ert-deftest ecss-cascade-test-literal-functions-are-never-called ()
  (let ((schemas (ecss-cascade-test--schemas)) (calls 0))
    (let* ((literal (lambda () (cl-incf calls)))
           (style (ecss-compute-style
                   schemas (ecss-cascade-test--subject)
                   :declarations (list 'app/payload literal))))
      (should (zerop calls))
      (should (functionp (ecss-cascade-test--value style 'app/payload))))))

(ert-deftest ecss-cascade-test-explicit-resolver-runs-once ()
  (let ((schemas (ecss-cascade-test--schemas)) (calls 0))
    (let* ((source (list :computed (lambda () (cl-incf calls) 42)))
           (style
            (ecss-compute-style
             schemas (ecss-cascade-test--subject)
             :declarations (list 'app/width source)
             :value-resolver
             (lambda (value _property _subject)
               (if (eq (car-safe value) :computed)
                   (funcall (cadr value))
                 value)))))
      (should (= calls 1))
      (should (= (ecss-cascade-test--value style 'app/width) 42)))))

(ert-deftest ecss-cascade-test-resolver-never-runs-for-losing-sources ()
  (let ((schemas (ecss-cascade-test--schemas))
        (stylesheet (ecss-stylesheet-create))
        (subject (ecss-cascade-test--subject :classes '("target")))
        (calls 0))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target"
     (list 'app/width (list :computed (lambda () (error "loser ran")))))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".other"
     (list 'app/width (list :computed (lambda () (error "unmatched ran")))))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/width 8))
    (let ((style
           (ecss-compute-style
            schemas subject :stylesheet stylesheet
            :value-resolver
            (lambda (value _property _subject)
              (cl-incf calls)
              (if (eq (car-safe value) :computed)
                  (funcall (cadr value))
                value)))))
      (should (= (ecss-cascade-test--value style 'app/width) 8))
      (should (= calls 1)))))

(ert-deftest ecss-cascade-test-resolver-skips-reverted-origin-losers ()
  (let ((schemas (ecss-cascade-test--schemas))
        (stylesheet (ecss-stylesheet-create))
        (subject (ecss-cascade-test--subject :classes '("target")))
        (calls 0))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/width 5) :origin 'ua)
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target"
     (list 'app/width (list :computed (lambda () (error "reverted loser ran"))))
     :origin 'author)
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target"
     (list 'app/width (ecss-wide-value 'revert)) :origin 'author)
    (let ((style
           (ecss-compute-style
            schemas subject :stylesheet stylesheet
            :value-resolver
            (lambda (value _property _subject)
              (cl-incf calls)
              (if (eq (car-safe value) :computed)
                  (funcall (cadr value))
                value)))))
      (should (= (ecss-cascade-test--value style 'app/width) 5))
      (should (= calls 2)))))

(ert-deftest ecss-cascade-test-selected-resolver-errors-propagate ()
  (let ((schemas (ecss-cascade-test--schemas)))
    (should-error
     (ecss-compute-style
      schemas (ecss-cascade-test--subject)
      :declarations '(app/width 1)
      :value-resolver
      (lambda (_value _property _subject) (error "resolver boom")))
     :type 'error)))

(ert-deftest ecss-cascade-test-rule-list-is-an-independent-snapshot ()
  (let ((schemas (ecss-cascade-test--schemas))
        (stylesheet (ecss-stylesheet-create))
        (subject (ecss-cascade-test--subject :classes '("target"))))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "snapshot"))
    (let ((rules (ecss-stylesheet-rules stylesheet)))
      (ecss-stylesheet-clear stylesheet)
      (should (equal (ecss-cascade-test--value
                      (ecss-compute-style schemas subject :rules rules)
                      'app/color)
                     "snapshot"))
      (should-error
       (ecss-compute-style
        schemas subject :stylesheet stylesheet :rules rules)
       :type 'ecss-invalid-rule))))

(ert-deftest ecss-cascade-test-rule-snapshot-is-revalidated ()
  (let ((schemas (ecss-cascade-test--schemas))
        (stylesheet (ecss-stylesheet-create))
        (subject (ecss-cascade-test--subject :classes '("target"))))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "snapshot"))
    (let ((rules (ecss-stylesheet-rules stylesheet)))
      (setf (ecss-rule-declarations (car rules)) '(foreign/value 1))
      (should-error (ecss-compute-style schemas subject :rules rules)
                    :type 'ecss-invalid-declaration))))

(ert-deftest ecss-cascade-test-authoring-getters-are-defensive ()
  (let ((schemas (ecss-cascade-test--schemas))
        (stylesheet (ecss-stylesheet-create)))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(app/color "blue") :layer '(theme base))
    (let ((schema (ecss-schema-set-property schemas 'app/color))
          (rules (ecss-stylesheet-rules stylesheet))
          (layers (ecss-stylesheet-layers stylesheet)))
      (setf (ecss-property-schema-initial schema) "damaged")
      (setf (ecss-rule-declarations (car rules)) '(app/color "damaged"))
      (setcar (car layers) 'damaged)
      (should (equal (ecss-property-schema-initial
                      (ecss-schema-set-property schemas 'app/color))
                     "black"))
      (should (equal (ecss-rule-declarations
                      (car (ecss-stylesheet-rules stylesheet)))
                     '(app/color "blue")))
      (should (equal (ecss-stylesheet-layers stylesheet)
                     '((theme base)))))))

(ert-deftest ecss-cascade-test-provenance-is-deterministic-and-defensive ()
  (let ((schemas (ecss-cascade-test--schemas))
        (stylesheet (ecss-stylesheet-create))
        (subject (ecss-cascade-test--subject :classes '("target"))))
    (ecss-stylesheet-add-rule
     stylesheet schemas ".target" '(--z 3 --a 1 app/color "blue"))
    (let* ((first (ecss-compute-style
                   schemas subject :stylesheet stylesheet :provenance t))
           (second (ecss-compute-style
                    schemas subject :stylesheet stylesheet :provenance t))
           (values (ecss-computed-style-values first))
           (facts (ecss-computed-style-provenance first)))
      (should (equal (ecss-computed-style-values first)
                     (ecss-computed-style-values second)))
      (should (equal facts (ecss-computed-style-provenance second)))
      (setcar values :damaged)
      (setcar facts :damaged)
      (should (equal (ecss-cascade-test--value first 'app/color) "blue"))
      (should-not (eq (car (ecss-computed-style-provenance first))
                      :damaged)))))

(ert-deftest ecss-cascade-test-computation-never-mutates-a-buffer ()
  (let ((schemas (ecss-cascade-test--schemas))
        (subject (ecss-cascade-test--subject)))
    (with-temp-buffer
      (insert "sentinel")
      (let ((before (buffer-string)))
        (cl-letf (((symbol-function 'insert)
                   (lambda (&rest _args) (error "buffer write")))
                  ((symbol-function 'delete-region)
                   (lambda (&rest _args) (error "buffer write")))
                  ((symbol-function 'add-text-properties)
                   (lambda (&rest _args) (error "buffer write")))
                  ((symbol-function 'put-text-property)
                   (lambda (&rest _args) (error "buffer write")))
                  ((symbol-function 'erase-buffer)
                   (lambda (&rest _args) (error "buffer write")))
                  ((symbol-function 'set-text-properties)
                   (lambda (&rest _args) (error "buffer write")))
                  ((symbol-function 'remove-text-properties)
                   (lambda (&rest _args) (error "buffer write"))))
          (should (ecss-computed-style-p
                   (ecss-compute-style
                    schemas subject :declarations '(app/color "blue")))))
        (should (equal (buffer-string) before))))))

(provide 'ecss-cascade-tests)
;;; ecss-cascade-tests.el ends here
