# Makefile for the ecss library.

EMACS ?= emacs
LOADPATH = -L . -L tests
PACKAGE_LINT_LOAD_EXTRA ?=
SRC = ecss-selector.el ecss-cascade.el ecss-file.el ecss.el
TESTS = $(wildcard tests/*-tests.el)

.PHONY: test compile compile-all checkdoc package-lint check clean diff-check

test: clean
	$(EMACS) -Q --batch $(LOADPATH) -l ecss.el \
	  $(patsubst %,-l %,$(TESTS)) -f ert-run-tests-batch-and-exit

compile: clean
	$(EMACS) -Q --batch $(LOADPATH) \
	  --eval '(setq byte-compile-error-on-warn t byte-compile-warnings (quote (not obsolete)))' \
	  -f batch-byte-compile $(SRC)

compile-all: clean
	$(EMACS) -Q --batch $(LOADPATH) \
	  --eval '(setq byte-compile-error-on-warn t byte-compile-warnings (quote (not obsolete)))' \
	  -f batch-byte-compile $(SRC) $(TESTS)

checkdoc:
	$(EMACS) -Q --batch $(LOADPATH) \
	  --eval '(progn (require (quote cl-lib)) (require (quote checkdoc)) \
	    (cl-letf (((symbol-function (quote display-warning)) \
	               (lambda (_type message &rest _args) (error "%s" message)))) \
	      (dolist (file (quote ("ecss-selector.el" "ecss-cascade.el" "ecss-file.el" "ecss.el"))) \
	        (checkdoc-file file))))'

package-lint:
	$(EMACS) -Q --batch $(LOADPATH) $(PACKAGE_LINT_LOAD_EXTRA) \
	  --eval '(progn (require (quote package-lint)) \
	    (setq package-lint-main-file "ecss.el") \
	    (dolist (file (quote ("ecss-selector.el" "ecss-cascade.el" "ecss-file.el" "ecss.el"))) \
	      (with-current-buffer (find-file-noselect file) \
	        (let ((issues (package-lint-buffer))) \
	          (when issues (error "package-lint failed for %s: %S" file issues))))))'

diff-check:
	git diff --check

check: compile-all test checkdoc diff-check
	$(MAKE) clean

clean:
	rm -f *.elc tests/*.elc
