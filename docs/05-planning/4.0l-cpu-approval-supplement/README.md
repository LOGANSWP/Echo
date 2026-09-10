# 4.0l CPU 兼容性增补审批

状态：待批准。原批准包继续有效；本增补未进入 App，也未修改原冻结包。

## 需要批准的具体变化

沿用 SmolVLM-256M 的同一源 revision `7e3e67edbbed1bf9888184d9df282b700a323964`，将解码器转换为 **FLOAT32 计算及权重、FP16 KV 状态**，替换原 FP16 解码器。视觉模型、分词器、图像预处理、提示词、上下文和输出限额保持原批准版本。

- 新解码器编译目录：`PinnedModels/photo-understanding-evaluation/smolvlm-256m/cpu-decoder-diagnostic/compiled/SmolDecoder1024.mlmodelc`。
- 新解码器 5 个文件共 **653,322,660 bytes**。全部拟部署资源及 NOTICE 共 **844,124,058 bytes**，逐文件 SHA-256 见 `candidate-resources.json`。
- 视觉模块体积预算由 **≤550 MB 调整为 ≤900 MB**。这是执行兼容性方案，不是更大模型或追求描述精确度；未下载新权重。
- 批准后只用于当前任务的本地 App 接线和双模拟器功能验证；CPU 路径采用此解码器。生产运行时保留完整资源验证，使用新工件身份，使旧 checkpoint 通过合法 Restart 更新，不混用旧身份。
- 原包的每图 60 秒、128 输出 token、4,096 UTF-8 bytes、context 1024、有限队列、隐私及删除约束保持。全 App 峰值 <1.5 GB 的验证要求保持，缺证据不能记通过。
- 不授予对外分发、实机、签名变更、PR 合并或最终质量/发布资格。

## 可复核证据

| 执行组合 | 三张合成无字图结果 |
|---|---|
| 原视觉 CPU + 原解码 CPU | 3/3 未正常 EOS，含协议 token/乱码，不能入库 |
| 原视觉 GPU + 原解码 CPU | 3/3 未正常 EOS |
| 原视觉 CPU + 原解码 GPU | 3/3 正常 EOS |
| 原视觉 CPU + 新 FLOAT32 解码 CPU | 3/3 正常 EOS，均为 `In this image there is a red circle.`，约 1.83–1.90 秒/张 |

上述均为 Mac 原生 Swift / ImageIO / Core ML 实际推理，不是手写描述或 Python 代推理。三图为方形、横图、竖图；真实 PhotoKit、模拟器完整 App 与双语创作仍未验收。`fp32-cpu.json` 保留具体 token、像素摘要和耗时。CPU/GPU 状态采样只说明首个 cache 已写入，不能证明全部状态运算正确。

原工件在 iOS 26.5 模拟器 CPU 路径同样拒绝非法生成 token；GPU 路径在加载解码器时出现 Core ML `std::bad_cast / -14`。新工件尚未取得进入 App 的批准，因此还不能声称它已解决模拟器问题。已证实的是同源 FLOAT32 转换解决了这组三图的 Mac CPU 功能失败；底层具体算子根因仍未确定。

新原生进程记录 RSS 历史峰值 **1,381,498,880 bytes**、内核 physical-footprint 历史峰值 **113,984,808 bytes**。两者计量范围不同；映射权重的 RSS 不等于 physical footprint，这也不是完整 Echo 同进程资源验收。加载、视觉与解码实例同时存在，后续必须在 App 内测释放与文本模型交接。

## 磁盘及供应链

研究目录目前约 **2.856 GB**（原工件、源权重、新诊断 package/compiled），仍在 3 GB 研究上限内；App 源资源、DerivedData 和模拟器安装副本另计。批准替换时先校验新工件，再替换本地 App 的旧解码器，不保留重复 App 资源备份。原批准的研究工件和冻结证据保留用于核对；清理本任务过期测试结果与临时探针。

无新模型下载或第三方依赖。许可及基础 SBOM 沿用原包；本目录 `NOTICE.md` 补充转换说明，`converter.py` 和 `conversion-manifest.json` 冻结本次转换来源与 package 身份，`PhotoStateProbe.swift` 记录诊断执行器。模型二进制继续忽略于 Git。

## 为什么需要增补审批

原批准包明确：“改变模型、量化、词表、实际预处理语义、语言策略或扩大预算时，需记录并评审具体差异；不能把审批套用到未知替代模型。”

本次改变解码工件与体积预算，因此原批准不能自动覆盖。依据为原冻结包 [README](../4.0l-approval-packet/README.md) 的“运行方案与预算”，以及 AGENTS.md §17.2 / ADR-023 的确切工件审批边界。批准对象为本目录 `packet-manifest.json` 的 SHA-256；`approval.json` 在明确批准前保持 pending。
