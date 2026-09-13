# ecss

[English](README.md)

`ecss` 是一个独立、纯计算、可扩展的 Emacs Lisp CSS 层叠引擎。它负责 selector、specificity、stylesheet、origin/importance、cascade layer、CSS-wide value、custom property、`var()`、inheritance、computed style 与 provenance；它不负责文本属性写入、响应式更新、Buffer 提交或 Box/Flex/Grid 布局。

这个仓库是全新的小写 `ecss` 项目，不修改、不依赖、也不兼容转发到历史大写 `ECSS` 仓库。

## 为什么能独立使用

`ecss` 不内置 Ebox 属性，也不要求 TP。普通程序可以注册自己的属性 vocabulary，用内置 `ecss-subject` 或 adapter 暴露任意树节点，然后取得纯数据 computed style。调用者自行决定这些值用于文本、Widget、DOM、布局、日志还是其他领域。

```elisp
(require 'ecss)

(let* ((package
        (ecss-schema-package-create
         'demo
         '((:id demo/color :initial "black" :inherits t
                :validator stringp :aliases (:color) :impacts (paint)))))
       (schemas (ecss-schema-set-compose package))
       (sheet (ecss-stylesheet-create))
       (button (ecss-subject-create
                :type "button" :classes '("primary"))))
  (ecss-stylesheet-add-rule
   sheet schemas "button.primary" '(demo/color "royalblue"))
  (ecss-computed-style-value
   (ecss-compute-style schemas button :stylesheet sheet)
   'demo/color))
;; => "royalblue"
```

## 核心边界

- `ecss-selector.el`：selector AST/parser/matcher/specificity 与通用 subject adapter。
- `ecss-cascade.el`：不可变 package schema、surface schema set、stylesheet、完整 winner 顺序、继承、变量解析和 provenance。
- `ecss.el`：公开 package facade；加载时没有行为副作用。
- package schema 与组合后的 schema set 不可变；stylesheet 只由显式 authoring API 修改；`ecss-compute-style` 不修改输入对象或当前 Buffer。
- 普通 function value 永远是普通值。只有调用者显式传入 `:value-resolver` 时，ECSS 才调用该 resolver；ECSS 自己不认识 TP binding、Ebox node 或任何业务 value-source 类型。

详细设计见 [架构](docs/architecture.zh-CN.md) 与 [API 参考](docs/manual.zh-CN.md)。

## 验证

```sh
make test EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs
make compile EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs
make checkdoc EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs
make package-lint EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs
make diff-check
```

`package-lint` 是开发期外部工具；如果它不在 `emacs -Q` 的 load-path 中，通过 `PACKAGE_LINT_LOAD_EXTRA='-L /path/to/package-lint'` 显式提供。它不是 `ecss` 的运行时依赖。

最低 Emacs 版本是 28.1。当前 package 版本是 0.1.0。

## 开发

克隆后运行 `make setup-hooks`。提交变更前运行 `make check`；`make structure-check` 用于快速检查目录、命名和引用。统一开发规则见 [AGENTS.md](AGENTS.md)。

[docs/manual.zh-CN.md](docs/manual.zh-CN.md) · [docs/architecture.zh-CN.md](docs/architecture.zh-CN.md) · [CHANGELOG.md](CHANGELOG.md)

`make check` 运行规范检查、编译及 [scripts/acceptance.json](scripts/acceptance.json) 中的公共验收场景。`make test` 运行更全面的回归测试；GUI 与性能验收使用独立入口。验收清单依据对外契约选择，不按当前能否通过筛选。
