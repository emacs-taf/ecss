# ecss API 参考

[English](api.en.md)

## Schema

- `(ecss-schema-set-create)` 创建隔离 registry。
- `(ecss-schema-set-define SCHEMAS ID &rest OPTIONS)` 原子注册 namespaced property。OPTIONS 是 `:initial`、`:inherits`、`:normalizer`、`:validator`、`:equality`、`:shorthand`。
- `(ecss-schema-set-property SCHEMAS ID)` 返回 defensive schema copy。
- `(ecss-schema-set-property-ids SCHEMAS)` 返回稳定注册顺序。
- `(ecss-expand-declarations SCHEMAS DECLARATIONS)` 校验属性并只展开一次 shorthand。
- `(ecss-merge-declarations SCHEMAS &rest DECLARATION-GROUPS)` 按从左到右的优先级展开并合并多组声明；后组覆盖相同 longhand，显式 nil 不会被当作缺省。

Property ID 必须是包含 `/` 的 symbol，例如 `demo/color`。Custom property 不需要 schema，使用 `--name` symbol。`initial` 在 schema 注册时规范化并校验一次；已计算的 initial/inherited value 不会再次执行 normalizer。

## Subject 与 selector

- `(ecss-subject-create &key type id classes attributes states parent children)` 创建内置 subject。
- `(ecss-subject-adapter-create &key type id classes attributes states parent children)` 为 caller-owned node 创建 adapter。
- `(ecss-selector-parse STRING)` 返回 AST。
- `(ecss-selector-normalize SELECTOR)` 接受 string 或 AST，返回 defensive AST。
- `(ecss-selector-match-p SELECTOR SUBJECT &optional ADAPTER)` 执行匹配。
- `(ecss-selector-specificity SELECTOR)` 返回 `(ID CLASS TYPE)`。

Parser 支持 selector list、compound selector、type/id/class、attribute presence/equality/token/language/prefix/suffix/substring、state pseudo、`:is()`、`:where()`、`:not()`、`:has()`，以及 descendant/child/adjacent/general-sibling combinator。`:has()` 使用相对 selector list，支持 `:has(> child)`、`:has(+ sibling)`、`:has(~ sibling)` 及其后续复合关系。未知 functional pseudo 被保存为 state token，由 adapter 的 `states` 决定是否匹配。

## Stylesheet

- `(ecss-stylesheet-create)` 创建隔离 stylesheet。
- `(ecss-stylesheet-declare-layers STYLESHEET LAYERS &optional ORIGIN)` 为一个 origin 预声明独立 layer order；ORIGIN 默认是 `author`。
- `(ecss-stylesheet-add-rule STYLESHEET SCHEMAS SELECTOR DECLARATIONS &key origin layer scope)` 原子添加 rule。
- `(ecss-stylesheet-rules STYLESHEET)` 与 `(ecss-stylesheet-layers STYLESHEET &optional ORIGIN)` 返回 defensive copies。
- `(ecss-stylesheet-clear STYLESHEET)` 清空显式对象。

ORIGIN 是 `ua`、`user`、`author`、`animation` 或 `transition`。Inline declarations 不放入 stylesheet，而通过 compute 的 `:declarations` 传入。

## Values 与 computation

- `(ecss-important VALUE)` 标记 `!important`。
- `(ecss-wide-value KIND)` 创建 `initial`、`inherit`、`unset`、`revert` 或 `revert-layer` tagged value；同名普通 symbol 保持普通值。
- `(ecss-var NAME &optional FALLBACK)` 创建 custom-property reference。
- `(ecss-compute-style SCHEMAS SUBJECT &key stylesheet rules declarations parent-style adapter provenance value-resolver)` 返回 `ecss-computed-style`。

不能同时传 `:stylesheet` 与 `:rules`。`:rules` 接受 `ecss-stylesheet-rules` 返回的 rule list，适用于不可变 snapshot 的保存和重放。`:parent-style` 可以是 computed style，也可以是已经计算完成的 values plist。`:provenance t` 才保留 winner facts。`:value-resolver` 的签名是 `(VALUE PROPERTY SUBJECT)`；未提供时 ECSS 不调用任何 property value。

## Computed style

- `(ecss-computed-style-values STYLE)` 返回 defensive values plist。
- `(ecss-computed-style-custom-properties STYLE)` 返回 deterministic custom-property plist。
- `(ecss-computed-style-active-properties STYLE)` 返回由有效 declaration 或 active inheritance 实际提供的 property ids，保留 explicit nil 与 absence 的区别；invalid winner 回退到 initial 时不伪装成 active declaration。
- `(ecss-computed-style-provenance STYLE)` 返回 winner、origin、important、layer、specificity、scope/source/declaration order、valid/fallback 等事实。
- `(ecss-computed-style-diagnostics STYLE)` 返回 custom-property cycle 等 deterministic diagnostics。
- `(ecss-computed-style-value STYLE PROPERTY &optional FALLBACK)` 读取单值。
- `(ecss-computed-style-present-p STYLE PROPERTY)` 判断 property 是否 active，即使值为 nil。

所有 aggregate getter 都返回 defensive copy。调用者修改返回值不会改变 computed style、schema set 或 stylesheet。
