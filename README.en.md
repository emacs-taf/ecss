# ecss

[中文](README.md)

`ecss` is an independent, pure, extensible CSS cascade engine for Emacs Lisp. It owns selectors, specificity, stylesheets, origins and importance, cascade layers, CSS-wide values, custom properties, `var()`, inheritance, computed styles, and provenance. It does not own text-property writes, reactive updates, buffer publication, or Box/Flex/Grid layout.

This repository is a new lowercase `ecss` project. It neither modifies nor depends on the historical uppercase `ECSS` repository, and it provides no forwarding compatibility layer to that project.

## Independent use

`ecss` does not embed Ebox properties and does not require TP. Any program can register its own property vocabulary, expose nodes through built-in `ecss-subject` values or an adapter, and receive a pure-data computed style. The caller decides whether those values drive text, widgets, a DOM, layout, diagnostics, or another domain.

```elisp
(require 'ecss)

(let ((schemas (ecss-schema-set-create))
      (sheet (ecss-stylesheet-create))
      (button (ecss-subject-create
               :type "button" :classes '("primary"))))
  (ecss-schema-set-define
   schemas 'demo/color :initial "black" :inherits t :validator #'stringp)
  (ecss-stylesheet-add-rule
   sheet schemas "button.primary" '(demo/color "royalblue"))
  (ecss-computed-style-value
   (ecss-compute-style schemas button :stylesheet sheet)
   'demo/color))
;; => "royalblue"
```

## Core boundary

- `ecss-selector.el` owns the selector AST, parser, matcher, specificity, and generic subject adapter.
- `ecss-cascade.el` owns explicit schema sets, stylesheets, complete winner ordering, inheritance, variable resolution, and provenance.
- `ecss.el` is the public package facade and has no behavioral load side effects.
- Schema sets and stylesheets change only through explicit authoring APIs. `ecss-compute-style` mutates neither its inputs nor the current buffer.
- An ordinary function value always remains a value. ECSS calls code only through an explicitly supplied `:value-resolver`; ECSS itself knows nothing about TP bindings, Ebox nodes, or consumer-specific value-source types.

See [Architecture](docs/architecture.en.md) and [API Reference](docs/api.en.md) for the complete contract.

## Verification

```sh
make test EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs
make compile EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs
make checkdoc EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs
make package-lint EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs
make diff-check
```

`package-lint` is an external development tool. If it is absent from the `emacs -Q` load path, provide it explicitly with `PACKAGE_LINT_LOAD_EXTRA='-L /path/to/package-lint'`. It is not an `ecss` runtime dependency.

The minimum Emacs version is 28.1. The current package version is 0.1.0.
