# 4.0k 确切工件审批材料

**状态：待人类审批。** 本材料将模型工件使用审批与产品验收分开：审批者可允许这个确切候选进入 4.0k 的 Core 实现、App 工程包与实机验证；任何审批都不把当前质量失败改为通过，也不授权发布、合并 PR 或降低既有门禁。

## 请求审批的具体方案

- 模型：**Qwen3-0.6B**，固定 revision `c1899de289a04d12100db370d81485cdf75e47ca`。
- 工件：**context1024、int8 per-channel、FP16 compute/KV**；使用 Xcode 26.5 编译的 `Qwen06BContext1024Int8Channel.mlmodelc`，共 5 个文件，**598,476,419 bytes**。完整清单在 [编译后 manifest](../4.0k-qwen3-int8-compiled-manifest.json)，不是仅校验一个定义文件。
- 附属资源：固定 `tokenizer.json`、`tokenizer_config.json`、`config.json`、`generation_config.json`、上游 LICENSE。模型加这些附属资源共 **609,921,113 bytes**，实际文件一一列于 [candidate-resources.json](candidate-resources.json)。第一方配置、NOTICE 和最终 App 编译的额外字节仍需最终打包核对。
- 运行时：系统 **Core ML + Foundation/NaturalLanguage + 第一方 Swift byte-BPE/受限解码器**。没有新增第三方 App 推理库，没有 Python 进入 App；当前原生探针的直接动态依赖全部来自 Apple 系统目录。
- 使用范围：本地创作与月/年报告所需的获批子集；仅 zh-Hans/en-US。随工程包分发，不在 App 内下载、不调用云端 AI。
- 许可处置：上游声明 Apache-2.0，完整 LICENSE、修改声明与工具原始通知已归档；**Model Legal/Privacy 审批者尚未签字**。本材料不自行提供商业分发批准。

源、转换包、编译目录和 tokenizer 的完整路径/长度/SHA-256 在 [artifact-inventory.json](artifact-inventory.json)。[runtime-lineage.json](runtime-lineage.json) 保存原生代码/二进制、转换与量化脚本、原始报告和工具链身份。审批后若改变模型、量化、tokenizer/template 或该清单的实质 scope，必须重新评审相应变化，不能套用本次批准。

## 需要一并确认的执行预算

| 项目 | 当前提案及验收方式 |
|---|---|
| 上下文 | 1024 tokens；完整 system/template/schema/来源与重试指令全部计数，预留输出 256，输入最多 768；超限拆批或显式失败 |
| 单调用 | 输出最多 256 tokens；60 秒截止；正文/JSON 不修复；每次最多一次语言重试，重试重新计入完整预算 |
| 报告总预算 | 最多 24 个来源；按 token 装入，每批最多 4 来源；fan-in 最多 4，最多 3 层；所有调用/重试/恢复重放合计最多 32 次、600 秒；无法收敛时失败或明确缩减 coverage |
| 会话与内存 | 同时最多一个模型会话；context1024 的 KV 为 112MiB；全 App 峰值仍须 **<1.5GB**，不能用文件大小或 Mac 单模型采样代替 |
| 工件体积 | 生成模块待批准目标 **≤650MB**，取代此前未批准的 ≤400MB 研究提案；最终压缩/thinning 单独测量。不改变全 App 内存门槛 |
| 中间数据 | envelope≤64KiB，中间正文总驻留≤512KiB；不保存草稿/KV 到恢复描述；实际 token 输出上限优先约束 |
| 设备/OS | 首个实机验证点为已只读发现的 iPhone 14 Plus / iOS 18.2.1；后续至少覆盖一台支持的 iOS 26 iPhone。最低部署仍为 iOS 18，未验证的设备范围保持 pending，不以模拟器代替 |
| 时延/取消 | 单调用≤60秒，执行尝试≤600秒；取消响应目标≤2秒，需要在实机证明单步不可取消区间；不承诺抢占正在执行的 GPU/ANE 操作 |
| 资源验证 | Release 工程包：3 次冷加载、20 次生成/取消，记录热状态、电量、计算单元；验证与 E5/SigLIP2/Whisper/UI 共存及资源释放，无截图/录像 |
| 正式质量 | 计划冻结 400 条合成案例（两种语言各 200，明确复用/参数化/独立来源分组）；实际案例文件与期望事实标注须在正式运行前冻结 SHA，当前 8 条不得冒充该验收集 |
| 语言门禁 | 首轮≥99%，自然语言失败最多一次重试且成功率≥95%；分母零=N/A。正文语言/脚本与人工可读性分别评判，不靠模型自报或正则删除正文放行 |
| 内容门禁提案 | 人工核对无无依据事实、无错误归因；至少95%案例覆盖其冻结 expected-facts；没有模型自评审批。该提案尚未获批，不能冒充既有 AC 已通过 |

本次可批准的是**工件与运行时使用及后续验证计划**；尚未形成的实际验收集、第二台实机证据、最终 App SBOM/哈希和所有测量结果仍是验收阻断项。任何“允许继续接线”的决定都不能被写成这些结果已经通过。

## 已有证据与保留的失败

- 原生完整链路复用 8 条开发样例：8/8 合法 envelope 与实际 allow-list，3,574 次预测、8 次生成；整轮约149秒。token IDs/解码与官方工具对照一致。见 [完整原生审查](../4.0k-native-generation-review.json)。
- 确切编译目录再次直接加载：45 次短前缀预测，8/8 参考最高分 token 匹配，前后 5 个文件均重新校验。未复制为生产 App，也未执行实机推理。
- 同一 Mac 原生进程观察到约974MB内核历史 footprint peak；这不是全 App 或实机门禁结果。
- 工具测试与实际 Swift tokenizer/grammar/budget 测试通过；真实预测返回后注入取消，未产生生成结果或完成事件。没有实机取消时延结论。
- **保留失败**：正文可能复述来源中的指令、在中文里保留 `upright`、将来源 UUID 放进正文、把第二条来源限定语扩写到第一条。主体语言筛查8/8不能覆盖这些问题。int8 没有通过此前 FP16 浮点误差阈值，该失败不删除也不改分。

因此当前**不建议批准产品发布或宣称模型质量已合格**。选择这个工件进行接线的理由是原生可运行、工件约610MB、有完整身份与可测预算；它仍需通过真实生产管线的语言对齐、分层、权限/删除/恢复、资源及正式质量验收。若最终不能过门禁，维持诚实不可用并更换工件或重新决策，不能用 fallback 报告结案。

## 许可证与 SBOM 阅读顺序

1. [NOTICE.md](NOTICE.md)：来源、版权、转换/量化修改与分发范围；上游 LICENSE 全文位于 `licenses/Qwen3-0.6B-LICENSE`。
2. [SBOM.cdx.json](SBOM.cdx.json)：CycloneDX 1.6 格式的候选及当前研究工具组件图；30 个 Python 工具组件、3 个模型阶段、4 个系统框架、1 个第一方运行时组件。
3. [licenses-index.json](licenses-index.json)：完整保存安装包随附的许可证/NOTICE（含其嵌入第三方归属）。tokenizers 许可是单独归档的上游版本参考，其 wheel 内缺失文本的事实保持可见。
4. 此 SBOM **不是最终 Echo App SBOM**；当前依赖快照不能倒推未记录的历史 wheel 身份。发布前应在冻结的构建环境补齐实际分发组件、最终完整文件清单和版权处置。Python 工具不会因为出现在转换清单中就被放进 App。

Apache 2.0 的重新分发条件要求保留许可、修改声明和适用的上游归属通知；此处归档不代替审批者的许可处置。[Apache 官方条款](https://www.apache.org/licenses/LICENSE-2.0)。SBOM 的格式按 [CycloneDX 1.6 官方 schema](https://raw.githubusercontent.com/CycloneDX/specification/1.6/schema/bom-1.6.schema.json) 独立验证。

## 审批记录

`approval.json` 初始保持 `pending`、批准人/时间为空。只在用户针对上述确切方案作出明确决定后记录原文、时间、scope 和本包 manifest SHA。Agent 不填写占位批准人、不自行将本包或生产能力标记为 approved。
