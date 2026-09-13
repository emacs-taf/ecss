# Changelog

All notable changes to `ecss` are documented here.

## 0.1.0 (Unreleased)

### Changed

- Expose the package entry at the repository root, document supported APIs in
  its Commentary and retain implementations under `lisp/`. Source consumers add
  the repository root to `load-path` and require the package entry; internal
  feature imports are unsupported. Archives retain this same directory layout.


### Added

- Independent property schemas, generic subjects and adapters, selector parsing and matching, stylesheets, complete cascade ordering, CSS-wide values, custom properties, computed values, diagnostics, and provenance.
- Pure Ebox-neutral public APIs with no TP dependency and no Buffer mutation.
- `ecss-merge-declarations` for shorthand-aware, presence-preserving composition of direct declaration groups.
- Standalone tests and compile, checkdoc, package-lint, and whitespace verification targets.
