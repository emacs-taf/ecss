# ecss API Reference

[中文](api.zh.md)

## Schemas

- `(ecss-schema-package-create PACKAGE-ID DEFINITIONS)` validates and snapshots one package's property definitions.
- `(ecss-schema-package-id PACKAGE)` and `(ecss-schema-package-property-ids PACKAGE)` return detached identity/index data.
- `(ecss-schema-set-compose &rest PACKAGES)` atomically composes one surface's immutable schema set. A package, canonical, or alias collision rejects the whole composition.
- `(ecss-schema-set-package-ids SCHEMAS)` and `(ecss-schema-set-property-ids SCHEMAS)` return stable composition order.
- `(ecss-schema-set-canonical-id SCHEMAS NAME)` resolves an exact alias to its canonical ID.
- `(ecss-schema-set-property SCHEMAS ID)` returns a defensive schema copy for a canonical ID or exact alias.
- `(ecss-schema-set-property-metadata SCHEMAS ID)` returns detached metadata.
- `(ecss-expand-declarations SCHEMAS DECLARATIONS)` validates properties and expands each shorthand once.
- `(ecss-merge-declarations SCHEMAS &rest DECLARATION-GROUPS)` expands and merges groups from left to right. Later groups replace the same longhand, while explicit nil remains a declaration.

Each definition is a plist containing `:id`, a nonempty `:impacts`, and optional `:initial`, `:inherits`, `:normalizer`, `:validator`, `:equality`, `:shorthand`, `:aliases`, `:projections`, and `:metadata`. A property ID is a symbol containing `/`, such as `demo/color`. Aliases exist only at declaration normalization. Canonical/alias, duplicate-alias, and shorthand/owned-longhand conflicts in one declaration are errors rather than implicit last-wins; later declaration groups still replace earlier groups.

Custom properties need no schema and use `--name` symbols. `initial` is normalized and validated once when the package is created; already computed initial and inherited values do not run the normalizer again. Packages and composed schema sets expose no mutator.

## Subjects and selectors

- `(ecss-subject-create &key type id classes attributes states parent children)` creates a built-in subject.
- `(ecss-subject-adapter-create &key type id classes attributes states parent children)` adapts caller-owned nodes.
- `(ecss-selector-parse STRING)` returns an AST.
- `(ecss-selector-normalize SELECTOR)` accepts a string or AST and returns a defensive AST.
- `(ecss-selector-match-p SELECTOR SUBJECT &optional ADAPTER)` matches a subject.
- `(ecss-selector-specificity SELECTOR)` returns `(ID CLASS TYPE)`.

The parser supports selector lists, compound selectors, type/id/class, attribute presence/equality/token/language/prefix/suffix/substring matching, state pseudos, `:is()`, `:where()`, `:not()`, `:has()`, and descendant/child/adjacent/general-sibling combinators. `:has()` accepts relative selector lists, including `:has(> child)`, `:has(+ sibling)`, `:has(~ sibling)`, and chained relationships. An unknown functional pseudo is preserved as a state token; the adapter's `states` result determines whether it matches.

## Stylesheets

- `(ecss-stylesheet-create)` creates an isolated stylesheet.
- `(ecss-stylesheet-declare-layers STYLESHEET LAYERS &optional ORIGIN)` predeclares an independent layer order for one origin. ORIGIN defaults to `author`.
- `(ecss-stylesheet-add-rule STYLESHEET SCHEMAS SELECTOR DECLARATIONS &key origin layer scope)` atomically adds a rule.
- `(ecss-stylesheet-rules STYLESHEET)` and `(ecss-stylesheet-layers STYLESHEET &optional ORIGIN)` return defensive copies.
- `(ecss-stylesheet-clear STYLESHEET)` clears the explicit object.

ORIGIN is `ua`, `user`, `author`, `animation`, or `transition`. Inline declarations do not enter a stylesheet; pass them as compute-time `:declarations`.

## Values and computation

- `(ecss-important VALUE)` tags `!important`.
- `(ecss-wide-value KIND)` creates a tagged `initial`, `inherit`, `unset`, `revert`, or `revert-layer` value. An ordinary symbol with the same name remains ordinary data.
- `(ecss-var NAME &optional FALLBACK)` creates a custom-property reference.
- `(ecss-compute-style SCHEMAS SUBJECT &key stylesheet rules declarations parent-style adapter provenance value-resolver)` returns an `ecss-computed-style`.

Do not pass both `:stylesheet` and `:rules`. `:rules` accepts the rule list returned by `ecss-stylesheet-rules` for immutable snapshot storage and replay. `:parent-style` may be a computed style or an already computed values plist. Winner facts are retained only with `:provenance t`. `:value-resolver` has signature `(VALUE PROPERTY SUBJECT)`; without it ECSS calls no property value.

## Computed styles

- `(ecss-computed-style-values STYLE)` returns a defensive values plist.
- `(ecss-computed-style-custom-properties STYLE)` returns a deterministic custom-property plist.
- `(ecss-computed-style-active-properties STYLE)` returns property IDs supplied by valid declarations or active inheritance, preserving explicit nil versus absence. An invalid winner falling back to the initial value is not presented as an active declaration.
- `(ecss-computed-style-specified-properties STYLE)` returns longhand property IDs that have cascade winners, independent of whether provenance was requested.
- `(ecss-computed-style-copy-with-values STYLE VALUES &key active-properties specified-properties)` returns an immutable-style copy for a consumer that has already proved selector/cascade facts unchanged and only needs to replace computed values.
- `(ecss-computed-style-provenance STYLE)` returns winner, origin, importance, layer, specificity, scope/source/declaration order, validity, and fallback facts.
- `(ecss-computed-style-diagnostics STYLE)` returns deterministic diagnostics such as custom-property cycles.
- `(ecss-computed-style-value STYLE PROPERTY &optional FALLBACK)` reads one detached value; PROPERTY may be canonical or an exact alias.
- `(ecss-computed-style-property-fact STYLE PROPERTY)` returns one detached typed fact containing the canonical property, computed value, owner, impact set, projections, winner provenance, and metadata. The same fact can be routed to multiple impact consumers without normalizing its value again.
- `(ecss-computed-style-present-p STYLE PROPERTY)` detects an active property even when its value is nil.
- `(ecss-computed-style-specified-p STYLE PROPERTY)` detects whether a longhand property has a cascade winner.

No public schema or computed getter exposes a mutable registry or computed-style object. Mutating a returned value cannot change a computed style, schema set, or stylesheet.
