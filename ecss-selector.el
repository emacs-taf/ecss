;;; ecss-selector.el --- Generic CSS selector model -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Geekinney
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; This module parses, validates, matches, and scores CSS-like selectors over
;; either `ecss-subject' values or caller-owned values exposed through an
;; `ecss-subject-adapter'.  It has no dependency on buffers or rendering code.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(define-error 'ecss-error "ECSS error")
(define-error 'ecss-invalid-selector "Invalid ECSS selector" 'ecss-error)
(define-error 'ecss-invalid-subject-adapter
  "Invalid ECSS subject adapter" 'ecss-error)

(cl-defstruct (ecss-subject (:constructor ecss--make-subject))
  "Generic selector subject independent of a rendering consumer."
  type id classes attributes states parent children)

(cl-defstruct (ecss-subject-adapter
               (:constructor ecss--make-subject-adapter))
  "Functions exposing caller-owned subjects to the selector engine."
  type id classes attributes states parent children)

(cl-defstruct (ecss--selector-parser
               (:constructor ecss--make-selector-parser))
  input position length)

(defconst ecss--attribute-operators '("=" "~=" "|=" "^=" "$=" "*=")
  "Supported attribute selector operators.")

(defconst ecss--selector-delimiters
  '(?\s ?\t ?\n ?\r ?\f ?. ?# ?\[ ?\] ?: ?, ?> ?+ ?~ ?\( ?\) ?*
    ?= ?| ?^ ?$ ?' ?\" ?/)
  "Characters that terminate an unescaped selector identifier.")

(defvar ecss--selector-anchor nil
  "Dynamically bound subject anchoring a relative selector.")

(defun ecss--copy-boundary-data (value)
  "Return a detached copy of mutable caller boundary VALUE.
Function values retain identity so executable literals remain callable."
  (cond
   ((functionp value) value)
   ((consp value)
    (cons (ecss--copy-boundary-data (car value))
          (ecss--copy-boundary-data (cdr value))))
   ((stringp value) (copy-sequence value))
   ((bool-vector-p value) (copy-sequence value))
   ((or (vectorp value) (recordp value))
    (let ((copy (copy-sequence value)))
      (dotimes (index (length copy))
        (aset copy index (ecss--copy-boundary-data (aref copy index))))
      copy))
   (t value)))

(defun ecss--adapter-callback-p (value)
  "Return non-nil when VALUE is a valid adapter callback."
  (functionp value))

(cl-defun ecss-subject-adapter-create
    (&key type id classes attributes states parent children)
  "Create a subject adapter from the supplied callbacks.
TYPE, ID, CLASSES, ATTRIBUTES, STATES, PARENT, and CHILDREN each accept one
caller-owned subject and return the named field."
  (let ((callbacks (list type id classes attributes states parent children)))
    (unless (cl-every #'ecss--adapter-callback-p callbacks)
      (signal 'ecss-invalid-subject-adapter callbacks)))
  (ecss--make-subject-adapter
   :type type :id id :classes classes :attributes attributes
   :states states :parent parent :children children))

(defconst ecss-default-subject-adapter
  (ecss--make-subject-adapter
   :type #'ecss-subject-type
   :id #'ecss-subject-id
   :classes #'ecss-subject-classes
   :attributes #'ecss-subject-attributes
   :states #'ecss-subject-states
   :parent #'ecss-subject-parent
   :children #'ecss-subject-children)
  "Adapter for built-in `ecss-subject' values.")

(cl-defun ecss-subject-create
    (&key type id classes attributes states parent children)
  "Create a generic subject.
TYPE and ID identify it.  CLASSES and STATES are token lists.  ATTRIBUTES is
an alist.  PARENT and CHILDREN establish its initial tree position."
  (when (and parent (not (ecss-subject-p parent)))
    (signal 'wrong-type-argument (list 'ecss-subject-p parent)))
  (let ((subject (ecss--make-subject
                  :type (ecss--copy-boundary-data type)
                  :id (ecss--copy-boundary-data id)
                  :classes (ecss--copy-boundary-data classes)
                  :attributes (ecss--copy-boundary-data attributes)
                  :states (ecss--copy-boundary-data states))))
    (ecss-subject-set-children subject children)
    (when parent
      (ecss-subject-set-children
       parent (append (ecss-subject-children parent) (list subject))))
    subject))

(defun ecss-subject-set-children (subject children)
  "Replace SUBJECT's CHILDREN and maintain their parent links."
  (unless (ecss-subject-p subject)
    (signal 'wrong-type-argument (list 'ecss-subject-p subject)))
  (unless (cl-every #'ecss-subject-p children)
    (signal 'wrong-type-argument (list 'ecss-subject-p children)))
  (dolist (old-child (ecss-subject-children subject))
    (when (eq (ecss-subject-parent old-child) subject)
      (setf (ecss-subject-parent old-child) nil)))
  (setf (ecss-subject-children subject) (copy-sequence children))
  (dolist (child children)
    (when-let ((old-parent (ecss-subject-parent child)))
      (unless (eq old-parent subject)
        (setf (ecss-subject-children old-parent)
              (delq child (ecss-subject-children old-parent)))))
    (setf (ecss-subject-parent child) subject))
  subject)

(defun ecss--adapter-call (adapter field subject)
  "Call ADAPTER callback FIELD for SUBJECT."
  (funcall
   (pcase field
     ('type (ecss-subject-adapter-type adapter))
     ('id (ecss-subject-adapter-id adapter))
     ('classes (ecss-subject-adapter-classes adapter))
     ('attributes (ecss-subject-adapter-attributes adapter))
     ('states (ecss-subject-adapter-states adapter))
     ('parent (ecss-subject-adapter-parent adapter))
     ('children (ecss-subject-adapter-children adapter)))
   subject))

(defun ecss--subject-parent (subject adapter)
  "Return SUBJECT's parent through ADAPTER."
  (ecss--adapter-call adapter 'parent subject))

(defun ecss--subject-children (subject adapter)
  "Return SUBJECT's children through ADAPTER."
  (ecss--adapter-call adapter 'children subject))

(defun ecss--parser-end-p (parser)
  "Return non-nil when PARSER reached the input end."
  (>= (ecss--selector-parser-position parser)
      (ecss--selector-parser-length parser)))

(defun ecss--parser-peek (parser &optional offset)
  "Return PARSER character at optional OFFSET without consuming it."
  (let ((position (+ (ecss--selector-parser-position parser) (or offset 0))))
    (when (< position (ecss--selector-parser-length parser))
      (aref (ecss--selector-parser-input parser) position))))

(defun ecss--parser-take (parser)
  "Consume and return PARSER's current character."
  (prog1 (ecss--parser-peek parser)
    (cl-incf (ecss--selector-parser-position parser))))

(defun ecss--selector-space-p (character)
  "Return non-nil when CHARACTER is CSS whitespace."
  (memq character '(?\s ?\t ?\n ?\r ?\f)))

(defun ecss--parser-skip-comment (parser)
  "Skip one comment at PARSER and return non-nil when found."
  (when (and (eq (ecss--parser-peek parser) ?/)
             (eq (ecss--parser-peek parser 1) ?*))
    (cl-incf (ecss--selector-parser-position parser) 2)
    (let ((end (string-match "\\*/" (ecss--selector-parser-input parser)
                             (ecss--selector-parser-position parser))))
      (unless end
        (signal 'ecss-invalid-selector (list :unclosed-comment)))
      (setf (ecss--selector-parser-position parser) (+ end 2)))
    t))

(defun ecss--parser-skip-space (parser)
  "Skip whitespace and comments at PARSER and report actual whitespace."
  (let (space progress)
    (while
        (progn
          (setq progress nil)
          (while (ecss--selector-space-p (ecss--parser-peek parser))
            (setq progress t space t)
            (ecss--parser-take parser))
          (when (ecss--parser-skip-comment parser)
            (setq progress t))
          progress))
    space))

(defun ecss--parser-skip-comments (parser)
  "Skip consecutive comments at PARSER without implying a combinator."
  (while (ecss--parser-skip-comment parser)))

(defun ecss--identifier-character-p (character)
  "Return non-nil when CHARACTER may occur unescaped in an identifier."
  (and character (not (memq character ecss--selector-delimiters))))

(defun ecss--parser-read-escape (parser)
  "Read one escaped character from PARSER."
  (ecss--parser-take parser)
  (when (ecss--parser-end-p parser)
    (signal 'ecss-invalid-selector (list :trailing-escape)))
  (ecss--parser-take parser))

(defun ecss--parser-read-identifier (parser)
  "Read and return one identifier from PARSER."
  (let (characters)
    (while (or (ecss--identifier-character-p (ecss--parser-peek parser))
               (eq (ecss--parser-peek parser) ?\\))
      (push (if (eq (ecss--parser-peek parser) ?\\)
                (ecss--parser-read-escape parser)
              (ecss--parser-take parser))
            characters))
    (unless characters
      (signal 'ecss-invalid-selector
              (list :expected-identifier
                    (ecss--selector-parser-position parser))))
    (apply #'string (nreverse characters))))

(defun ecss--parser-expect (parser character)
  "Consume CHARACTER from PARSER or signal an invalid-selector error."
  (unless (eq (ecss--parser-peek parser) character)
    (signal 'ecss-invalid-selector
            (list :expected character
                  :position (ecss--selector-parser-position parser))))
  (ecss--parser-take parser))

(defun ecss--parser-read-string (parser)
  "Read one quoted string from PARSER."
  (let ((quote (ecss--parser-take parser)) characters done)
    (while (and (not done) (not (ecss--parser-end-p parser)))
      (let ((character (ecss--parser-take parser)))
        (cond ((eq character quote) (setq done t))
              ((eq character ?\\)
               (when (ecss--parser-end-p parser)
                 (signal 'ecss-invalid-selector (list :trailing-escape)))
               (push (ecss--parser-take parser) characters))
              (t (push character characters)))))
    (unless done
      (signal 'ecss-invalid-selector (list :unclosed-string)))
    (apply #'string (nreverse characters))))

(defun ecss--parser-read-attribute-value (parser)
  "Read one attribute value from PARSER."
  (if (memq (ecss--parser-peek parser) '(?' ?\"))
      (ecss--parser-read-string parser)
    (ecss--parser-read-identifier parser)))

(defun ecss--parser-attribute-operator (parser)
  "Read an optional attribute operator from PARSER."
  (let ((first (ecss--parser-peek parser))
        (second (ecss--parser-peek parser 1)))
    (cond ((eq first ?=) (ecss--parser-take parser) "=")
          ((and (memq first '(?~ ?| ?^ ?$ ?*)) (eq second ?=))
           (cl-incf (ecss--selector-parser-position parser) 2)
           (string first second)))))

(defun ecss--parser-read-attribute (parser)
  "Read one attribute selector from PARSER."
  (ecss--parser-expect parser ?\[)
  (ecss--parser-skip-space parser)
  (let ((name (ecss--parser-read-identifier parser)) operator value flag)
    (ecss--parser-skip-space parser)
    (setq operator (ecss--parser-attribute-operator parser))
    (when operator
      (ecss--parser-skip-space parser)
      (setq value (ecss--parser-read-attribute-value parser))
      (ecss--parser-skip-space parser)
      (when (and (ecss--identifier-character-p (ecss--parser-peek parser))
                 (not (eq (ecss--parser-peek parser) ?\])))
        (setq flag (downcase (ecss--parser-read-identifier parser)))
        (unless (member flag '("i" "s"))
          (signal 'ecss-invalid-selector (list :attribute-flag flag)))
        (ecss--parser-skip-space parser)))
    (ecss--parser-expect parser ?\])
    (if operator
        (list :attr name operator value flag)
      (list :attr name))))

(defun ecss--parser-read-raw-function (parser)
  "Read an unknown pseudo function argument from PARSER."
  (let ((start (ecss--selector-parser-position parser))
        (depth 1) quote escaped)
    (while (and (> depth 0) (not (ecss--parser-end-p parser)))
      (let ((character (ecss--parser-take parser)))
        (cond (escaped (setq escaped nil))
              ((eq character ?\\) (setq escaped t))
              (quote (when (eq character quote) (setq quote nil)))
              ((memq character '(?' ?\")) (setq quote character))
              ((eq character ?\() (cl-incf depth))
              ((eq character ?\)) (cl-decf depth)))))
    (unless (zerop depth)
      (signal 'ecss-invalid-selector (list :unclosed-pseudo)))
    (string-trim
     (substring (ecss--selector-parser-input parser) start
                (1- (ecss--selector-parser-position parser))))))

(defun ecss--anchor-relative-selector (selector kind)
  "Anchor relative SELECTOR with leading combinator KIND."
  (if (memq (car-safe selector) '(:descendant :child :adjacent :sibling))
      (list (car selector)
            (ecss--anchor-relative-selector (nth 1 selector) kind)
            (nth 2 selector))
    (list kind '(:anchor) selector)))

(defun ecss--parser-read-relative-list (parser)
  "Read a relative selector list from PARSER through its closing parenthesis."
  (ecss--parser-skip-space parser)
  (let (selectors done)
    (while (not done)
      (let ((kind (or (ecss--combinator-kind (ecss--parser-peek parser))
                      :descendant)))
        (unless (eq kind :descendant)
          (ecss--parser-take parser)
          (ecss--parser-skip-space parser))
        (push (ecss--anchor-relative-selector
               (ecss--parser-read-complex parser ?\)) kind)
              selectors))
      (ecss--parser-skip-space parser)
      (cond ((eq (ecss--parser-peek parser) ?,)
             (ecss--parser-take parser)
             (ecss--parser-skip-space parser))
            ((eq (ecss--parser-peek parser) ?\))
             (ecss--parser-take parser)
             (setq done t))
            (t (signal 'ecss-invalid-selector (list :unterminated-relative)))))
    (nreverse selectors)))

(defun ecss--parser-read-pseudo (parser)
  "Read one pseudo-class selector from PARSER."
  (ecss--parser-expect parser ?:)
  (when (eq (ecss--parser-peek parser) ?:)
    (signal 'ecss-invalid-selector (list :pseudo-elements-unsupported)))
  (let ((name (downcase (ecss--parser-read-identifier parser))))
    (if (not (eq (ecss--parser-peek parser) ?\())
        (list :state name)
      (ecss--parser-take parser)
      (cond
       ((equal name "has")
        (cons :has (ecss--parser-read-relative-list parser)))
       ((member name '("is" "where" "not"))
          (let ((selectors (ecss--parser-read-selector-list parser ?\))))
            (cons (intern (concat ":" name))
                  (if (eq (car-safe selectors) :list)
                      (cdr selectors)
                    (list selectors)))))
       (t (list :state
                (list name (ecss--parser-read-raw-function parser))))))))

(defun ecss--compound-item-p (character)
  "Return non-nil when CHARACTER can start a compound selector item."
  (memq character '(?# ?. ?\[ ?:)))

(defun ecss--parser-read-compound (parser)
  "Read one compound selector from PARSER."
  (let (items)
    (cond ((eq (ecss--parser-peek parser) ?*)
           (ecss--parser-take parser)
           (push '(:universal) items))
          ((ecss--identifier-character-p (ecss--parser-peek parser))
           (push (list :type (ecss--parser-read-identifier parser)) items)))
    (ecss--parser-skip-comments parser)
    (while (ecss--compound-item-p (ecss--parser-peek parser))
      (pcase (ecss--parser-peek parser)
        (?# (ecss--parser-take parser)
            (push (list :id (ecss--parser-read-identifier parser)) items))
        (?. (ecss--parser-take parser)
            (push (list :class (ecss--parser-read-identifier parser)) items))
        (?\[ (push (ecss--parser-read-attribute parser) items))
        (?: (push (ecss--parser-read-pseudo parser) items)))
      (ecss--parser-skip-comments parser))
    (setq items (nreverse items))
    (cond ((null items)
           (signal 'ecss-invalid-selector
                   (list :expected-compound
                         (ecss--selector-parser-position parser))))
          ((null (cdr items)) (car items))
          (t (cons :and items)))))

(defun ecss--combinator-kind (character)
  "Return AST combinator kind for CHARACTER."
  (pcase character (?> :child) (?+ :adjacent) (?~ :sibling)))

(defun ecss--selector-list-end-p (parser terminator)
  "Return non-nil when PARSER is at a list boundary TERMINATOR."
  (or (ecss--parser-end-p parser)
      (eq (ecss--parser-peek parser) ?,)
      (and terminator (eq (ecss--parser-peek parser) terminator))))

(defun ecss--parser-read-complex (parser terminator)
  "Read one complex selector from PARSER up to TERMINATOR."
  (let ((left (ecss--parser-read-compound parser)) done)
    (while (not done)
      (let ((space (ecss--parser-skip-space parser)) kind)
        (cond ((ecss--selector-list-end-p parser terminator)
               (setq done t))
              ((setq kind (ecss--combinator-kind (ecss--parser-peek parser)))
               (ecss--parser-take parser)
               (ecss--parser-skip-space parser)
               (setq left (list kind left
                                (ecss--parser-read-compound parser))))
              (space
               (setq left (list :descendant left
                                (ecss--parser-read-compound parser))))
              (t
               (signal 'ecss-invalid-selector
                       (list :unexpected-character
                             (ecss--parser-peek parser)))))))
    left))

(defun ecss--parser-read-selector-list (parser &optional terminator)
  "Read a selector list from PARSER up to optional TERMINATOR."
  (ecss--parser-skip-space parser)
  (let (selectors done)
    (while (not done)
      (push (ecss--parser-read-complex parser terminator) selectors)
      (ecss--parser-skip-space parser)
      (cond ((eq (ecss--parser-peek parser) ?,)
             (ecss--parser-take parser)
             (ecss--parser-skip-space parser))
            ((and terminator (eq (ecss--parser-peek parser) terminator))
             (ecss--parser-take parser)
             (setq done t))
            ((and (null terminator) (ecss--parser-end-p parser))
             (setq done t))
            (t (signal 'ecss-invalid-selector (list :unterminated-list)))))
    (setq selectors (nreverse selectors))
    (if (null (cdr selectors)) (car selectors) (cons :list selectors))))

;;;###autoload
(defun ecss-selector-parse (selector)
  "Parse CSS-like SELECTOR text into a structured selector AST."
  (unless (and (stringp selector) (not (string-empty-p selector)))
    (signal 'ecss-invalid-selector (list selector)))
  (let ((parser (ecss--make-selector-parser
                 :input selector :position 0 :length (length selector))))
    (ecss--parser-read-selector-list parser)))

(defun ecss--selector-form-p (selector kind arity)
  "Return non-nil when SELECTOR is KIND with ARITY arguments."
  (and (consp selector) (eq (car selector) kind)
       (= (length (cdr selector)) arity)))

(defun ecss--selector-list-valid-p (selectors)
  "Return non-nil when SELECTORS is a nonempty valid selector list."
  (and selectors (cl-every #'ecss-selector-valid-p selectors)))

(defun ecss--attribute-selector-valid-p (selector)
  "Return non-nil when attribute SELECTOR is valid."
  (or (ecss--selector-form-p selector :attr 1)
      (and (ecss--selector-form-p selector :attr 4)
           (member (nth 2 selector) ecss--attribute-operators)
           (or (null (nth 4 selector))
               (member (nth 4 selector) '("i" "s"))))))

(defun ecss-selector-valid-p (selector)
  "Return non-nil when structured SELECTOR is valid."
  (pcase (car-safe selector)
    ((or :type :id :class :state)
     (and (ecss--selector-form-p selector (car selector) 1)
          (nth 1 selector)))
    (:attr (ecss--attribute-selector-valid-p selector))
    ((or :and :list :is :where :not :has)
     (ecss--selector-list-valid-p (cdr selector)))
    ((or :descendant :child :adjacent :sibling)
     (and (ecss--selector-form-p selector (car selector) 2)
          (ecss--selector-list-valid-p (cdr selector))))
    ((or :universal :anchor) (null (cdr selector)))
    (_ nil)))

(defun ecss--validate-selector (selector)
  "Return SELECTOR or signal when it is invalid."
  (unless (ecss-selector-valid-p selector)
    (signal 'ecss-invalid-selector (list selector)))
  selector)

;;;###autoload
(defun ecss-selector-normalize (selector)
  "Return a validated defensive AST for string or structured SELECTOR."
  (let ((ast (if (stringp selector) (ecss-selector-parse selector) selector)))
    (ecss--copy-boundary-data (ecss--validate-selector ast))))

(defun ecss--selector-subject-local-p (selector)
  "Return non-nil when validated SELECTOR reads only its subject."
  (pcase (car selector)
    ((or :universal :type :id :class :state :attr) t)
    ((or :and :list :is :where :not)
     (cl-every #'ecss--selector-subject-local-p (cdr selector)))
    (_ nil)))

;;;###autoload
(defun ecss-selector-subject-local-p (selector)
  "Return non-nil when SELECTOR depends only on the matched subject.

Subject-local selectors may inspect type, id, classes, attributes, states,
and local logical combinations such as `:is' and `:not'.  Selectors involving
ancestors, children, or siblings return nil.  Invalid selectors signal
`ecss-invalid-selector'."
  (ecss--selector-subject-local-p (ecss-selector-normalize selector)))

(defun ecss--subject-attribute-cell (subject adapter name)
  "Return SUBJECT attribute NAME through ADAPTER."
  (assoc name (ecss--adapter-call adapter 'attributes subject)))

(defun ecss--subject-previous-siblings (subject adapter)
  "Return SUBJECT's preceding siblings through ADAPTER."
  (when-let ((parent (ecss--subject-parent subject adapter)))
    (let ((siblings (ecss--subject-children parent adapter)) result)
      (while (and siblings (not (eq (car siblings) subject)))
        (push (pop siblings) result))
      (nreverse result))))

(defun ecss--attribute-token-member-p (needle value insensitive)
  "Return whether NEEDLE occurs in whitespace-separated VALUE.
Compare without case when INSENSITIVE is non-nil."
  (let ((tokens (split-string (format "%s" value) "[ \t\n\r\f]+" t)))
    (cl-some (lambda (token)
               (if insensitive
                   (string-equal (downcase needle) (downcase token))
                 (string-equal needle token)))
             tokens)))

(defun ecss--attribute-string-match-p (operator expected actual insensitive)
  "Match EXPECTED against ACTUAL with OPERATOR and case mode INSENSITIVE."
  (let ((expected (format "%s" expected)) (actual (format "%s" actual)))
    (when insensitive
      (setq expected (downcase expected) actual (downcase actual)))
    (cond ((equal operator "=") (string-equal actual expected))
          ((equal operator "~=")
           (ecss--attribute-token-member-p expected actual insensitive))
          ((equal operator "|=")
           (or (string-equal actual expected)
               (string-prefix-p (concat expected "-") actual)))
          ((equal operator "^=") (string-prefix-p expected actual))
          ((equal operator "$=") (string-suffix-p expected actual))
          ((equal operator "*=")
           (string-match-p (regexp-quote expected) actual)))))

(defun ecss--selector-match-attribute (selector subject adapter)
  "Return whether attribute SELECTOR matches SUBJECT through ADAPTER."
  (let ((cell (ecss--subject-attribute-cell subject adapter (nth 1 selector))))
    (and cell
         (or (= (length selector) 2)
             (ecss--attribute-string-match-p
              (nth 2 selector) (nth 3 selector) (cdr cell)
              (equal (nth 4 selector) "i"))))))

(defun ecss--selector-match-descendant (selector subject adapter)
  "Return whether descendant SELECTOR matches SUBJECT through ADAPTER."
  (and (ecss-selector-match-p (nth 2 selector) subject adapter)
       (cl-loop for parent = (ecss--subject-parent subject adapter)
                then (ecss--subject-parent parent adapter)
                while parent
                thereis (ecss-selector-match-p
                         (nth 1 selector) parent adapter))))

(defun ecss--selector-match-adjacent (selector subject adapter)
  "Return whether adjacent SELECTOR matches SUBJECT through ADAPTER."
  (let ((siblings (ecss--subject-previous-siblings subject adapter)))
    (and siblings
         (ecss-selector-match-p (nth 1 selector) (car (last siblings)) adapter)
         (ecss-selector-match-p (nth 2 selector) subject adapter))))

(defun ecss--selector-match-sibling (selector subject adapter)
  "Return whether sibling SELECTOR matches SUBJECT through ADAPTER."
  (and (ecss-selector-match-p (nth 2 selector) subject adapter)
       (cl-some (lambda (sibling)
                  (ecss-selector-match-p (nth 1 selector) sibling adapter))
                (ecss--subject-previous-siblings subject adapter))))

(defun ecss--subject-descendants (subject adapter)
  "Return all descendants of SUBJECT through ADAPTER."
  (cl-loop for child in (ecss--subject-children subject adapter)
           append (cons child (ecss--subject-descendants child adapter))))

(defun ecss--subject-following-siblings (subject adapter)
  "Return siblings following SUBJECT through ADAPTER."
  (when-let ((parent (ecss--subject-parent subject adapter)))
    (let ((siblings (ecss--subject-children parent adapter)))
      (while (and siblings (not (eq (pop siblings) subject))))
      siblings)))

(defun ecss--relative-candidates (subject adapter)
  "Return possible relative-selector targets from SUBJECT through ADAPTER."
  (append
   (ecss--subject-descendants subject adapter)
   (cl-loop for sibling in (ecss--subject-following-siblings subject adapter)
            append (cons sibling (ecss--subject-descendants sibling adapter)))))

(defun ecss--selector-match-has (selectors subject adapter)
  "Return whether SUBJECT has a relative target matching SELECTORS."
  (let ((ecss--selector-anchor subject))
    (cl-some (lambda (candidate)
               (cl-some (lambda (selector)
                          (ecss-selector-match-p selector candidate adapter))
                        selectors))
             (ecss--relative-candidates subject adapter))))

(defun ecss--selector-match-valid (selector subject adapter)
  "Match validated SELECTOR against SUBJECT through ADAPTER."
  (pcase (car selector)
    (:universal t)
    (:anchor (eq subject ecss--selector-anchor))
    (:type (equal (nth 1 selector) (ecss--adapter-call adapter 'type subject)))
    (:id (equal (nth 1 selector) (ecss--adapter-call adapter 'id subject)))
    (:class (member (nth 1 selector)
                    (ecss--adapter-call adapter 'classes subject)))
    (:state (member (nth 1 selector)
                    (ecss--adapter-call adapter 'states subject)))
    (:attr (ecss--selector-match-attribute selector subject adapter))
    (:and (cl-every (lambda (item)
                      (ecss-selector-match-p item subject adapter))
                    (cdr selector)))
    ((or :list :is :where)
     (cl-some (lambda (item)
                (ecss-selector-match-p item subject adapter))
              (cdr selector)))
    (:not (not (cl-some (lambda (item)
                          (ecss-selector-match-p item subject adapter))
                        (cdr selector))))
    (:has (ecss--selector-match-has (cdr selector) subject adapter))
    (:descendant (ecss--selector-match-descendant selector subject adapter))
    (:child (and (ecss-selector-match-p (nth 2 selector) subject adapter)
                 (when-let ((parent (ecss--subject-parent subject adapter)))
                   (ecss-selector-match-p (nth 1 selector) parent adapter))))
    (:adjacent (ecss--selector-match-adjacent selector subject adapter))
    (:sibling (ecss--selector-match-sibling selector subject adapter))))

;;;###autoload
(defun ecss-selector-match-p
    (selector subject &optional adapter)
  "Return non-nil when SELECTOR matches SUBJECT through optional ADAPTER."
  (let ((adapter (or adapter ecss-default-subject-adapter))
        (selector (if (stringp selector)
                      (ecss-selector-parse selector)
                    selector)))
    (unless (ecss-subject-adapter-p adapter)
      (signal 'wrong-type-argument (list 'ecss-subject-adapter-p adapter)))
    (ecss--validate-selector selector)
    (ecss--selector-match-valid selector subject adapter)))

(defun ecss--specificity-add (left right)
  "Add specificity triples LEFT and RIGHT."
  (cl-mapcar #'+ left right))

(defun ecss--specificity-greater-p (left right)
  "Return non-nil when specificity LEFT is greater than RIGHT."
  (catch 'result
    (cl-mapc (lambda (a b)
               (cond ((> a b) (throw 'result t))
                     ((< a b) (throw 'result nil))))
             left right)
    nil))

(defun ecss--specificity-max (values)
  "Return the lexicographically greatest specificity in VALUES."
  (cl-reduce (lambda (left right)
               (if (ecss--specificity-greater-p left right) left right))
             values :initial-value '(0 0 0)))

(defun ecss--specificity-list-sum (selectors)
  "Return the combined specificity of SELECTORS."
  (cl-reduce #'ecss--specificity-add selectors
             :key #'ecss-selector-specificity
             :initial-value '(0 0 0)))

;;;###autoload
(defun ecss-selector-specificity (selector)
  "Return SELECTOR specificity as an (ID CLASS TYPE) list."
  (setq selector (if (stringp selector)
                     (ecss-selector-parse selector)
                   selector))
  (ecss--validate-selector selector)
  (pcase (car selector)
    (:id '(1 0 0))
    ((or :class :attr :state) '(0 1 0))
    (:type '(0 0 1))
    ((or :universal :anchor :where) '(0 0 0))
    (:and (ecss--specificity-list-sum (cdr selector)))
    ((or :list :is :not :has)
     (ecss--specificity-max
      (mapcar #'ecss-selector-specificity (cdr selector))))
    ((or :descendant :child :adjacent :sibling)
     (ecss--specificity-list-sum (cdr selector)))))

(defun ecss--selector-matched-specificity (selector subject adapter)
  "Return matched specificity for SELECTOR, SUBJECT, and ADAPTER, or nil."
  (when (ecss-selector-match-p selector subject adapter)
    (if (eq (car selector) :list)
        (ecss--specificity-max
         (cl-loop for item in (cdr selector)
                  when (ecss-selector-match-p item subject adapter)
                  collect (ecss-selector-specificity item)))
      (ecss-selector-specificity selector))))

(provide 'ecss-selector)
;;; ecss-selector.el ends here
