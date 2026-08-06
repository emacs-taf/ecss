# ecss 架构

[English](architecture.en.md)

## 定位

`ecss` 是“规则如何赢、最终属性值是什么”的通用纯计算层。它把 consumer 提供的 property schemas、subjects、stylesheets、inline declarations 与 parent computed style 转换成 computed values、custom properties、active properties、provenance 和 diagnostics。

```text
consumer schemas + subject adapter + stylesheet + parent style
                              │
                              ▼
       selector match → candidate collection → cascade winner
                              │
                              ▼
        CSS-wide/custom-property resolution → normalize/validate
                              │
                              ▼
              computed style + provenance + diagnostics
```

`ecss` 不知道 computed values 最终如何显示。TP 可以把最终文本属性贡献转换成 retained surface patch；Ebox 可以把最终 Box/Flex/Grid 属性解释成 measurement、layout 与 painting 后果；普通调用者也可以完全不用 TP/Ebox。

## 显式对象而不是进程全局状态

每个 consumer 创建自己的 `ecss-schema-set` 与 `ecss-stylesheet`。两个应用可以在同一 Emacs 中使用同名 selector token、不同 property vocabulary 和不同 layer 顺序而互不污染；同一 stylesheet 中的 UA、user 与 author origin 也分别维护自己的 layer order。schema 注册与 rule 添加是显式、原子的 authoring 操作；一次失败不会留下半注册 schema、半添加 layer 或错误 source order。

## Subject 与 adapter

简单场景直接使用 `ecss-subject`。已有树模型通过 `ecss-subject-adapter-create` 提供 type、id、classes、attributes、states、parent 与 children callback，不需要把业务节点复制成 ECSS node。selector query 与 stylesheet 都调用同一个 parser、matcher 和 specificity 实现，因此不会出现“查询能匹配但样式规则不能匹配”的两套语义。

## Cascade 顺序

候选值按 CSS 顺序比较：relevance/match、origin+importance、cascade layer、specificity、scope proximity、source order、declaration order。标准 origin level 是 UA normal、user normal、author normal、animation、author important、user important、UA important、transition。normal layer 后声明者优先且 unlayered 高于 layered；important layer 反向，inline author declaration 在 author origin 内保持最高优先级。

`revert` 删除当前整个 origin 后重新选择，不区分 normal 与 important；`revert-layer` 删除当前 origin 中的整个 layer 后重新选择。invalid-at-computed-value 不会退回较低候选，而是使用 inherited/initial fallback，并在 provenance 中记录 invalid winner。

## Value source 边界

ECSS 不自动调用属性里的 function，也不定义自己的 reactive/computed wrapper。调用者需要求值时，显式向 `ecss-compute-style` 传入 `:value-resolver`。resolver 接收 value、property、subject，ECSS 对每个被选中的 source 只调用一次，resolver 返回值不会被二次执行。resolver error 直接向外传播；由于 computation 是纯计算，不存在需要 ECSS 回滚的 Buffer 或 runtime state。

## Custom properties

Custom properties 使用 `--name` symbol，通过普通 cascade 选出 raw value，默认从 parent computed style 继承，再用 `ecss-var` 解析。引用可以嵌套在 list/vector 中；缺失值与 cycle 可使用引用处 fallback。cycle 不破坏整个 computed style，而产生 deterministic diagnostic，并把受影响 value 标记为 invalid-at-computed-value。

## 三包边界

```text
ecss: selector / stylesheet / cascade / computed values
tp:   text-property contributions / reactive runtime / diff / transaction / buffer commit
ebox: box semantics / measurement / flex-grid layout / painting / dirty ownership
```

允许的依赖方向是 Ebox 消费 `ecss` 与 TP；`ecss` 和 TP 可以彼此完全独立使用。`ecss` public API 不出现 TP object/binding/mount、Ebox node、marker、patch 或 buffer mutation。
