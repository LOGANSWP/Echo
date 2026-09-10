---
library_name: transformers
license: apache-2.0
language:
- en
pipeline_tag: text-generation
tags:
- safetensors
- onnx
- transformers.js
base_model:
- HuggingFaceTB/SmolLM2-135M
---


# SmolLM2

![image/png](https://cdn-uploads.huggingface.co/production/uploads/61c141342aac764ce1654e43/3ntM63zkmxY2cNRhgY_Kl.png)

##  Table of Contents

1. [Model Summary](##model-summary)
2. [Limitations](##limitations)
3. [Training](##training)
4. [License](##license)
5. [Citation](##citation)

## Model Summary

SmolLM2 is a family of compact language models available in three size: 135M, 360M, and 1.7B parameters. They are capable of solving a wide range of tasks while being lightweight enough to run on-device. More details in our paper https://arxiv.org/abs/2502.02737 

SmolLM2 demonstrates significant advances over its predecessor SmolLM1, particularly in instruction following, knowledge, reasoning. The 135M model was trained on 2 trillion tokens using a diverse dataset combination: FineWeb-Edu, DCLM, The Stack, along with new filtered datasets we curated and will release soon.  We developed the instruct version through supervised fine-tuning (SFT) using a combination of public datasets and our own curated datasets. We then applied Direct Preference Optimization (DPO) using [UltraFeedback](https://huggingface.co/datasets/HuggingFaceH4/ultrafeedback_binarized).

The instruct model additionally supports tasks such as text rewriting, summarization and function calling (for the 1.7B) thanks to datasets developed by [Argilla](https://huggingface.co/argilla) such as [Synth-APIGen-v0.1](https://huggingface.co/datasets/argilla/Synth-APIGen-v0.1).
You can find the SFT dataset here: https://huggingface.co/datasets/HuggingFaceTB/smol-smoltalk and finetuning code at https://github.com/huggingface/alignment-handbook/tree/main/recipes/smollm2

### How to use

### Transformers
```bash
pip install transformers
```

```python
from transformers import AutoModelForCausalLM, AutoTokenizer
checkpoint = "HuggingFaceTB/SmolLM2-135M-Instruct"

device = "cuda" # for GPU usage or "cpu" for CPU usage
tokenizer = AutoTokenizer.from_pretrained(checkpoint)
# for multiple GPUs install accelerate and do `model = AutoModelForCausalLM.from_pretrained(checkpoint, device_map="auto")`
model = AutoModelForCausalLM.from_pretrained(checkpoint).to(device)

messages = [{"role": "user", "content": "What is gravity?"}]
input_text=tokenizer.apply_chat_template(messages, tokenize=False)
print(input_text)
inputs = tokenizer.encode(input_text, return_tensors="pt").to(device)
outputs = model.generate(inputs, max_new_tokens=50, temperature=0.2, top_p=0.9, do_sample=True)
print(tokenizer.decode(outputs[0]))
```

### Chat in TRL
You can also use the TRL CLI to chat with the model from the terminal:
```bash
pip install trl
trl chat --model_name_or_path HuggingFaceTB/SmolLM2-135M-Instruct --device cpu
```

### Transformers.js

```bash
npm i @huggingface/transformers
```

```js
import { pipeline } from "@huggingface/transformers";

// Create a text generation pipeline
const generator = await pipeline(
  "text-generation",
  "HuggingFaceTB/SmolLM2-135M-Instruct",
);

// Define the list of messages
const messages = [
  { role: "system", content: "You are a helpful assistant." },
  { role: "user", content: "What is the capital of France?" },
];

// Generate a response
const output = await generator(messages, { max_new_tokens: 128 });
console.log(output[0].generated_text.at(-1).content);
// "The capital of France is Paris."
```


## Evaluation

In this section, we report the evaluation results of SmolLM2. All evaluations are zero-shot unless stated otherwise, and we use [lighteval](https://github.com/huggingface/lighteval) to run them.

## Base pre-trained model

| Metrics            | SmolLM2-135M-8k | SmolLM-135M  |
|:-------------------|:----------------:|:------------:|
| HellaSwag         | **42.1**         | 41.2         |
| ARC (Average)     | **43.9**         | 42.4         |
| PIQA              | 68.4             | 68.4         |
| MMLU (cloze)      | **31.5**         | 30.2         |
| CommonsenseQA     | **33.9**         | 32.7         |
| TriviaQA          | 4.1              | **4.3**      |
| Winogrande        | 51.3             | 51.3         |
| OpenBookQA        | **34.6**         | 34.0         |
| GSM8K (5-shot)    | **1.4**          | 1.0          |


## Instruction model

| Metric                       | SmolLM2-135M-Instruct | SmolLM-135M-Instruct |
|:-----------------------------|:---------------------:|:--------------------:|
| IFEval (Average prompt/inst) | **29.9**                 | 17.2                |
| MT-Bench                     | **19.8**                 | 16.8                |
| HellaSwag                    | **40.9**                 | 38.9                |
| ARC (Average)                | **37.3**                 | 33.9                |
| PIQA                         | **66.3**                 | 64.0                |
| MMLU (cloze)                 | **29.3**                 | 28.3                |
| BBH (3-shot)                 | **28.2**                 | 25.2                |
| GSM8K (5-shot)               | 1.4                  | 1.4                 |



## Limitations

SmolLM2 models primarily understand and generate content in English. They can produce text on a variety of topics, but the generated content may not always be factually accurate, logically consistent, or free from biases present in the training data. These models should be used as assistive tools rather than definitive sources of information. Users should always verify important information and critically evaluate any generated content.

## Training

### Model

- **Architecture:** Transformer decoder
- **Pretraining tokens:** 2T
- **Precision:** bfloat16

### Hardware

- **GPUs:** 64 H100

### Software

- **Training Framework:** [nanotron](https://github.com/huggingface/nanotron/tree/main)

## License

[Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)

## Citation
```bash
@misc{allal2025smollm2smolgoesbig,
      title={SmolLM2: When Smol Goes Big -- Data-Centric Training of a Small Language Model}, 
      author={Loubna Ben Allal and Anton Lozhkov and Elie Bakouch and Gabriel Martín Blázquez and Guilherme Penedo and Lewis Tunstall and Andrés Marafioti and Hynek Kydlíček and Agustín Piqueres Lajarín and Vaibhav Srivastav and Joshua Lochner and Caleb Fahlgren and Xuan-Son Nguyen and Clémentine Fourrier and Ben Burtenshaw and Hugo Larcher and Haojun Zhao and Cyril Zakka and Mathieu Morlon and Colin Raffel and Leandro von Werra and Thomas Wolf},
      year={2025},
      eprint={2502.02737},
      archivePrefix={arXiv},
      primaryClass={cs.CL},
      url={https://arxiv.org/abs/2502.02737}, 
}
```