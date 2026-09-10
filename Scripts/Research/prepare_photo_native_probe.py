#!/usr/bin/env python3
"""Freeze non-media inputs/oracles for the native 4.0l probe, using local weights."""

import hashlib
import json
import os
import time
from pathlib import Path

os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
os.environ['TOKENIZERS_PARALLELISM'] = 'false'

from photo_understanding_probe import ROOT, SOURCE, verify_source


def main():
    verify_source()
    import numpy as np
    import torch
    from PIL import Image
    from transformers import AutoModelForImageTextToText, AutoProcessor

    torch.set_num_threads(4)
    torch.set_grad_enabled(False)
    processor = AutoProcessor.from_pretrained(str(SOURCE), local_files_only=True, trust_remote_code=False)
    model = AutoModelForImageTextToText.from_pretrained(str(SOURCE), local_files_only=True,
        trust_remote_code=False, dtype=torch.float32, attn_implementation='eager').eval()
    prompt = processor.apply_chat_template([{'role': 'user', 'content': [
        {'type': 'image'}, {'type': 'text', 'text': 'Describe this image in one short sentence.'}]}],
        add_generation_prompt=True, tokenize=False)
    vocab = [processor.tokenizer.convert_ids_to_tokens(i) for i in range(49280)]
    document = {'vocabulary': vocab, 'expectedPixels': []}
    cases = []
    for index in (0, 1):
        y, x = np.indices((512, 512))
        inside = (x-256)**2 + (y-256)**2 <= 112**2
        rgb = np.full((512, 512, 3), 255, dtype=np.uint8)
        rgb[inside] = (255, 0, 0) if index == 0 else (0, 0, 255)
        document['expectedPixels'].append(hashlib.sha256(rgb.tobytes()).hexdigest())
        batch = processor(text=prompt, images=[Image.fromarray(rgb)], return_tensors='pt',
                          do_image_splitting=False, size={'longest_edge': 512})
        ids = batch.input_ids[0].tolist()
        assert len(ids) <= 768 and ids.count(49190) == 64
        expected_pixels = (rgb.transpose(2, 0, 1).astype(np.float32) / 255 - 0.5) / 0.5
        assert np.array_equal(expected_pixels, batch.pixel_values[0, 0].numpy())
        if 'promptIDs' in document:
            assert document['promptIDs'] == ids
        document['promptIDs'] = ids
        start = time.monotonic()
        generated = model.generate(**batch, max_new_tokens=128, max_time=60,
                                   do_sample=False, use_cache=True)[0, len(ids):].tolist()
        cases.append({'id': index, 'generatedIDs': generated,
                      'text': processor.tokenizer.decode(generated, skip_special_tokens=True),
                      'eos': generated[-1] == 49279, 'seconds': time.monotonic()-start})
    input_path = SOURCE.parent / 'native-input.json'
    with input_path.open('x') as stream:
        json.dump(document, stream, ensure_ascii=False)
    report = {'taskId': '4.0l', 'scope': 'CPU FP32 analytic-circle oracles for native execution comparison; not content quality qualification',
              'sourceManifestSha256': hashlib.sha256((ROOT / 'docs/05-planning/4.0l-source-verification.json').read_bytes()).hexdigest(),
              'scriptSha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'nativeInputSha256': hashlib.sha256(input_path.read_bytes()).hexdigest(),
              'prompt': prompt, 'promptIDs': document['promptIDs'], 'pixelSha256': document['expectedPixels'], 'cases': cases}
    with (ROOT / 'docs/05-planning/4.0l-native-reference.json').open('x') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps(cases), flush=True)


if __name__ == '__main__':
    main()
