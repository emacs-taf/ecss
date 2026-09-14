# ecss 使用手册

[English](manual.md)

## Schema

- `(ecss-schema-package-create PACKAGE-ID DEFINITIONS)` 一次校验并快照一个 package 的属性定义。
- `(ecss-schema-package-id PACKAGE)` 与 `(ecss-schema-package-property-ids PACKAGE)` 返回 detached identity/index 信息。
- `(ecss-schema-set-compose &rest PACKAGES)` 原子组合一个 surface 的不可变 schema set；package、canonical 与 alias 冲突都会使整次组合失败。
- `(ecss-schema-set-package-ids SCHEMAS)` 与 `(ecss-schema-set-property-ids SCHEMAS)` 返回稳定组合顺序。
- `(ecss-schema-set-canonical-id SCHEMAS NAME)` 把 exact alias 解析为 canonical ID。
- `(ecss-schema-set-property SCHEMAS ID)` 返回 defensive schema copy；`ID` 可以是 canonical 或 exact alias。
- `(ecss-schema-set-property-metadata SCHEMAS ID)` 返回 detached metadata。
- `(ecss-expand-declarations SCHEMAS DECLARATIONS)` 校验属性并只展开一次 shorthand。
- `(ecss-merge-declarations SCHEMAS &rest DECLARATION-GROUPS)` 按从左到右的优先级展开并合并多组声明；后组覆盖相同 longhand，显式 nil 不会被当作缺省。

每个 definition 是包含 `:id`、非空 `:impacts`，以及可选 `:initial`、`:inherits`、`:normalizer`、`:validator`、`:equality`、`:shorthand`、`:aliases`、`:projections`、`:metadata` 的 plist。Property ID 必须是包含 `/` 的 symbol，例如 `demo/color`。Alias 只存在于声明归一化入口；同一声明中 canonical/alias、重复 alias 或 shorthand/owned-longhand 冲突会报错，不采用隐式 last-wins。不同 declaration group 仍由后组覆盖前组。

Custom property 不需要 schema，使用 `--name` symbol。`initial` 在 package 创建时规范化并校验一次；已计算的 initial/inherited value 不会再次执行 normalizer。Package 与组合后的 schema set 没有公共 mutator。

## Subject 与 selector

- `(ecss-subject-create &key type id classes attributes states parent children)` 创建内置 subject。
- `(ecss-subject-adapter-create &key type id classes attributes states parent children)` 为 caller-owned node 创建 adapter。
- `(ecss-selector-parse STRING)` 返回 AST。
- `(ecss-selector-normalize SELECTOR)` 接受 string 或 AST，返回 defensive AST。
- `(ecss-selector-match-p SELECTOR SUBJECT &optional ADAPTER)` 执行匹配。
- `(ecss-selector-specificity SELECTOR)` 返回 `(ID CLASS TYPE)`。

Parser 支持 selector list、compound selector、type/id/class、attribute presence/equality/token/language/prefix/suffix/substring、state pseudo、`:is()`、`:where()`、`:not()`、`:has()`，以及 descendant/child/adjacent/general-sibling combinator。`:has()` 使用相对 selector list，支持 `:has(> child)`、`:has(+ sibling)`、`:has(~ sibling)` 及其后续复合关系。未知 functional pseudo 被保存为 state token，由 adapter 的 `states` 决定是否匹配。

增量宿主可以用 `ecss-selector-subject-local-p` 分类选择器，再决定能否复用匹配。
默认情况下，作用域锚点和树关系不属于局部依赖。只有宿主已证明 subject 相对于
同一个作用域根的关系不变，才能传入可选的作用域根稳定参数，允许 `&` 和
`:scope`。例如 `(ecss-selector-subject-local-p "&.active" t)` 返回非 nil，
而 `"& > .active"` 仍返回 nil。复用计算样式前，宿主还必须分别检查本地元数据、
规则成员资格、层叠输入和继承值。详见[公共接口契约](../ecss.el)。

## Stylesheet

- `(ecss-stylesheet-create)` 创建隔离 stylesheet。
- `(ecss-stylesheet-declare-layers STYLESHEET LAYERS &optional ORIGIN)` 为一个 origin 预声明独立 layer order；ORIGIN 默认是 `author`。
- `(ecss-stylesheet-add-rule STYLESHEET SCHEMAS SELECTOR DECLARATIONS &key origin layer scope)` 原子添加 rule。
- `(ecss-stylesheet-rules STYLESHEET)` 与 `(ecss-stylesheet-layers STYLESHEET &optional ORIGIN)` 返回 defensive copies。
- `(ecss-stylesheet-clear STYLESHEET)` 清空显式对象。

ORIGIN 是 `ua`、`user`、`author`、`animation` 或 `transition`。Inline declarations 不放入 stylesheet，而通过 compute 的 `:declarations` 传入。

## 挂载作用域与样式所有权

宿主通过 `ecss-scope-create` 挂载 stylesheet 快照，再通过
`ecss-compute-style` 的 `:scopes` 提供所有活动作用域。普通选择器匹配严格
后代，`&` 与 `:scope` 匹配挂载根。`:subjects` 列表按 `eq` 身份限定规则目标；
省略时允许所有后代，显式 nil 表示没有目标。非法列表在返回作用域之前触发
`wrong-type-argument`。列表和 stylesheet 均被快照保存；节点树仍由宿主拥有，
宿主必须在作用域存续期间维持稳定的 adapter 身份。所有权改变时创建新作用域。

目标归属独立于物理父子关系：调用者的 slot 内容可以在子组件之下继续接受调用者
规则，同时排除子组件的 fallback。结构选择器仍在挂载根以内使用 adapter 树，
包括不在目标集合中的节点；目标集合不改变兄弟编号或继承。列出的节点若不在
挂载子树内也不会匹配。可选 `:parent` 只记录作用域关联，不自动添加父规则或
改变目标集合；需要两个作用域时显式传入二者。全局规则与行内声明不受影响。

```elisp
(let* ((schemas (ecss-schema-set-compose
                 (ecss-schema-package-create
                  'demo '((:id demo/color :initial "black"
                           :validator stringp :impacts (paint))))))
       (root (ecss-subject-create))
       (child (ecss-subject-create :parent root))
       (slot (ecss-subject-create :parent child :classes '("title")))
       (fallback (ecss-subject-create :parent child :classes '("title")))
       (sheet (ecss-stylesheet-create)))
  (ecss-stylesheet-add-rule sheet schemas ".title" '(demo/color "blue"))
  (let ((scope (ecss-scope-create root sheet :subjects (list root slot))))
    (mapcar (lambda (subject)
              (ecss-computed-style-value
               (ecss-compute-style schemas subject :scopes (list scope))
               'demo/color))
            (list slot fallback))))
;; => ("blue" "black")
```

## Values 与 computation

- `(ecss-important VALUE)` 标记 `!important`。
- `(ecss-wide-value KIND)` 创建 `initial`、`inherit`、`unset`、`revert` 或 `revert-layer` tagged value；同名普通 symbol 保持普通值。
- `(ecss-var NAME &optional FALLBACK)` 创建 custom-property reference。
- `(ecss-compute-style SCHEMAS SUBJECT &key stylesheet rules declarations parent-style adapter provenance value-resolver)` 返回 `ecss-computed-style`。

不能同时传 `:stylesheet` 与 `:rules`。`:rules` 接受 `ecss-stylesheet-rules` 返回的 rule list，适用于不可变 snapshot 的保存和重放。`:parent-style` 可以是 computed style，也可以是已经计算完成的 values plist。`:provenance t` 才保留 winner facts。`:value-resolver` 的签名是 `(VALUE PROPERTY SUBJECT)`；未提供时 ECSS 不调用任何 property value。

层叠前，宿主可用 `ecss-declaration-value-valid-p` 配合具体值谓词校验输入。
importance 不改变底层值的语法；CSS-wide 值和变量引用留到上下文解析后由
schema 校验。通过 `ecss-declaration-value-tagged-p` 可识别不能直接显示的
声明值。上下文值预检返回真不代表最终值有效；`ecss-compute-style` 仍会在
解析后应用 schema。

## Computed style

- `(ecss-computed-style-values STYLE)` 返回 defensive values plist。
- `(ecss-computed-style-custom-properties STYLE)` 返回 deterministic custom-property plist。
- `(ecss-computed-style-active-properties STYLE)` 返回由有效 declaration 或 active inheritance 实际提供的 property ids，保留 explicit nil 与 absence 的区别；invalid winner 回退到 initial 时不伪装成 active declaration。
- `(ecss-computed-style-specified-properties STYLE)` 返回存在 cascade winner 的长手 property ids，独立于是否请求 provenance。
- `(ecss-computed-style-precedence-winner STYLE PROPERTIES)` 返回这些 canonical property 已选 winner 中 cascade 优先级最高的 property ID；不会重跑 cascade，也不要求公开 provenance。
- `(ecss-computed-style-copy-with-values STYLE VALUES &key active-properties specified-properties)` 在 selector/cascade 事实已证明不变、只需替换 computed values 时返回新的 immutable-style copy。
- `(ecss-computed-style-provenance STYLE)` 返回 winner、origin、important、layer、specificity、scope/source/declaration order、valid/fallback 等事实。
- `(ecss-computed-style-diagnostics STYLE)` 返回 custom-property cycle 等 deterministic diagnostics。
- `(ecss-computed-style-value STYLE PROPERTY &optional FALLBACK)` 读取 detached 单值；PROPERTY 可以是 canonical 或 exact alias。
- `(ecss-computed-style-property-fact STYLE PROPERTY)` 返回一个 detached typed fact，包含 canonical property、computed value、owner、impact set、projections、winner provenance 与 metadata。同一个 fact 可同时交给多个 impact consumer，不重新规范化其 value。
- `(ecss-computed-style-present-p STYLE PROPERTY)` 判断 property 是否 active，即使值为 nil。
- `(ecss-computed-style-specified-p STYLE PROPERTY)` 判断长手 property 是否存在 cascade winner。

所有公共 schema/computed getter 都不会暴露 registry 或 computed style 的可变内部对象。调用者修改返回值不会改变 computed style、schema set 或 stylesheet。

## 静态规则数据

`.ecss` 文件只保存一份有序列表，不加 quote 或 `styles` 包装：

```elisp
((".title" :color "#334155")
 (".title.active" :font-weight bold))
```

文件使用 `ecss-file-read`，编辑器源字符串使用 `ecss-read-rules`。两者都只读
数据、允许注释并拒绝多余表达式。空样式表写作 `nil` 或 `()`；空白文件属于
未完成输入。值从不执行。普通 Elisp 调用方按语言规则引用字面量列表，或用
`list` 构造，然后通过 `ecss-validate-rules` 校验同一语法。选择器采用 ECSS
语义，属性是否合法仍由接收方 schema 决定。计算前将规则配合 schema 加入
显式 stylesheet；来源、层和作用域继续通过 stylesheet API 表达，基础文件
列表不取代这些构造接口。
