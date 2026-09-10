# 4.0l 确切视觉工件与 App 功能接线审批

**状态：待用户批准这份确切工件进入本地 App 工程验证。研究下载与实验已获批准，无需再次批准相同下载。**

## 本次请求

批准固定 **SmolVLM-256M** 的以下资源用于 `4.0l` 本地 App 功能实现与双模拟器验证：

- 源 revision：`7e3e67edbbed1bf9888184d9df282b700a323964`，原授权下 14 个文件均已校验。
- 视觉编码器/投影：`SmolVision512.mlmodelc`；文本解码器：`SmolDecoder1024.mlmodelc`。两者 FP16、iOS 18.0 编译目标，**10 文件合计 514,162,725 bytes**。
- 两模型、固定 tokenizer/config/template 与必要许可资源合计 **517,775,460 bytes（约 518 MB）**。逐文件路径、长度和 SHA-256 见 [candidate-resources.json](candidate-resources.json)；源、转换和编译身份见 [artifact-inventory.json](artifact-inventory.json)。
- 第一方 Swift tokenizer、ImageIO 图像预处理、Core ML 状态解码原型与工具链身份见 [runtime-lineage.json](runtime-lineage.json)。没有新增第三方 App 推理依赖，没有 Python 进入 App。
- 本次批准允许把这些确切资源放入被 Git 忽略的本地 App 模型资源目录，登记工件，并按 ADR-025 实现 Actor、派生描述/OCR 存储、队列/恢复、当前来源授权、创作/报告及 D-005。不得以资源登记代替授权校验。
- 沿用功能闭环优先：先验证真实照片无需编辑即可进入本地描述、创作、来源跳转和复制/分享；质量缺陷继续追踪，不要求先提高准确率或更换更大的模型。

**此请求不包含对外分发、发布、签名调整、PR 合并或实机验证授权，也不宣称现有质量、资源、隐私或覆盖率验收已通过。** 实机与正式发布资格仍按既有阶段安排处理。

## 运行方案与预算

| 项目 | 拟批准的实现边界 |
|---|---|
| 图像输入 | 单图；编码数据上限 32,000,000 bytes；头部尺寸每边最多 16,384、总像素最多 100,000,000；ImageIO 原生缩小至最长边不超过 512、应用方向、不拉伸；有效 patch 位置和 padding mask 显式传入模型 |
| 预处理身份 | `echo-photo-imageio-v1`；sRGB、透明部分合成白底、RGB 归一化到 [-1,1]、归一化后补零；不同于官方 Pillow 默认缩放实现，必须记录该独立版本，不能声称像素逐项等同所有上游 resize 路径 |
| 模型输入 | 一图 64 个视觉 token；完整输入最多 768 token、context 1024；Swift 对完整固定模板与提示真实分词，不以字符数代替 token |
| 输出 | 最多 128 token、4,096 UTF-8 bytes；60 秒单次截止；空/截断/非法协议 token/取消不 publication；上下文不隐式扩容 |
| 提示身份 | `echo-photo-caption-v1`，固定 `Describe this image in one short sentence.`；提示只用于观察，不授权执行图片内指令。任意来源文字仍作为不可信数据进入后续生成 |
| 中间语言 | 允许内部保存如实标为 `en-US` 的机器观察，带原 MemoryID 和模型/来源/处理版本；不伪装原文或中文输出。用户可见的最终生成继续由既有 `preferredLanguage`/Language Aligner 校验；中文 UI 不直接把英文机器中间文本冒充已完成中文描述 |
| 串行与释放 | 同时最多一个视觉会话；每图新 state，完成/失败/取消后释放模型与 KV；释放视觉资源后再执行既有文本生成。Mac 两进程串行证据不能替代 App 同进程释放实测 |
| 调度 | 单 job 最多 8 张照片，队列串行；逐图保存不含原图/正文的 checkpoint；旧照片分页准备，幂等去重。生产确切 schema/typed launcher 按 ADR-025 TDD 交付 |
| 重试与失败 | 不用高准确率筛选阻断功能接线；磁盘/可恢复失败按 L2 仅用户重试，缺失/损坏工件显式不可用，资源不足延后。最终生成语言重试继续遵守既有最多一次规则和预算 |
| 资源 | 新视觉模块目标 ≤550 MB；研究目录仍 ≤3 GB，及时清理本任务不再需要的缓存/重复制品；全 App 峰值 <1.5 GB 的后续验证要求保持原样，未测不记通过 |
| 功能设备 | iPhone 17 Pro / iOS 26.5 与 iPhone 16 Pro / iOS 18.x；构建/单测使用 17 Pro，测试串行。采用真实 PhotoKit 的无 PII 图片，不用 fixture/直写描述证明闭环，不保存截图/视频 |

这份工件批准覆盖按上述语义进行的第一方生产适配及必要测试，原型代码不是已完成的生产 Actor。改变模型、量化、词表、实际预处理语义、语言策略或扩大预算时，需记录并评审具体差异；不能把审批套用到未知替代模型。

## 已有功能证据

- **分词**：103 个官方 tokenizer 对照通过，覆盖中英文、组合字符、数字、空白和安全的完整提示框架；4 个输入限额拒绝通过。固定词表缺少部分 byte symbol，原生实现显式拒绝，避免静默丢字；不宣称支持任意 Unicode。
- **图片**：12 个方向/尺寸/mask 测试通过，含八种 TIFF 方向与横竖等比缩放；3 个无效/超限输入拒绝通过。尚未用实际 PhotoKit JPEG/HEIC 闭环替代这些研究输入。
- **真实 Core ML**：原生生成三种比例的内存无字图；Swift 自行生成提示 token、ImageIO 解码、运行两个真实模型并输出描述。两包与精确 `.mlmodelc` 直接加载分别跑通，均 EOS；编译工件前后完整哈希未变化。
- **取消**：一次实际视觉预测后触发 Task 取消，无解码调用和描述 publication；无在途预测抢占或实机取消时延声明。
- **语言与来源组合**：两张已完成原生推理的图片 × zh-Hans/en-US，共四次既有原生生成器调用；JSON、EOS、来源 allow-list 和正文语言全部通过。输入确实来自本次视觉结果，不是手写 caption。英文输出有重复段落，记录为后续质量优化项。
- **编译**：Swift 6、完整并发检查、warnings-as-errors 编译通过。对应检查点见 [原生功能证据](../4.0l-native-input-review.md)。

这些证据让 App 接线具备可执行的模型基础；它们仍不是 Echo 生产依赖图、真实 PhotoKit、同进程资源或正式内容质量验收。

## 许可与供应链材料

模型及其声明的 SigLIP、SmolLM2-Instruct 来源均声明 Apache-2.0；完整 Apache 条款、固定模型卡及其哈希保存在 [model-license-evidence.json](model-license-evidence.json) 和 `licenses/`。基础模型 revision 用于冻结此次许可证据，不冒充上游未提供的历史训练权重溯源。

[NOTICE.md](NOTICE.md) 记录来源、转换和修改；[SBOM.cdx.json](SBOM.cdx.json) 包含候选、第一方原型、系统框架与当前研究工具依赖图；[licenses-index.json](licenses-index.json) 保留安装包附带的完整许可/NOTICE。Python 工具只用于开发机转换与对照，不随 App 分发。这不是最终 App SBOM，也不代表 Agent 自行给出分发许可批准。

## 审批记录

[approval.json](approval.json) 保持 `pending`；在用户针对本包明确批准后，记录原话、时间及 `packet-manifest.json` 的 SHA-256。批准后继续当前 `4.0l` 分支上的生产实现，不重复下载研究模型，不开启新任务，不自动合并 PR。
