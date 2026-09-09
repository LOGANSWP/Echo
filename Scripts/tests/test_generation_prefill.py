"""Task 4.0k: batched prefill must preserve causal state and next-token logits."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import convert_generation_prefill as converter


class GenerationPrefillTests(unittest.TestCase):
    def test_AC1_chunked_prefill_matches_single_tokens_and_official_prefix(self):
        import torch
        from transformers import Qwen3Config, Qwen3ForCausalLM
        torch.set_num_threads(2)
        torch.manual_seed(4)
        config = Qwen3Config(hidden_size=32, num_attention_heads=4, num_key_value_heads=2,
                            head_dim=16, intermediate_size=64, num_hidden_layers=2,
                            vocab_size=64, max_position_embeddings=128)
        config._attn_implementation = 'eager'
        model = Qwen3ForCausalLM(config).eval()
        wrapper = converter.build_wrapper(model, context=1024)
        tokens = [4, 9, 2, 6, 1, 8, 5, 3, 12]
        with torch.inference_mode():
            single = []
            for offset, token in enumerate(tokens):
                single.append(wrapper(torch.tensor([[token]], dtype=torch.int32),
                                      torch.tensor([offset], dtype=torch.int32)).clone())
            wrapper.reset()
            for start, end in [(0, 4), (4, 8), (8, 9)]:
                actual = wrapper(torch.tensor([tokens[start:end]], dtype=torch.int32),
                                 torch.arange(start, end, dtype=torch.int32))
                expected = model(torch.tensor([tokens[:end]]), use_cache=False).logits[:, -1, :]
                torch.testing.assert_close(actual, single[end-1], atol=0.002, rtol=0.002)
                torch.testing.assert_close(actual, expected, atol=0.002, rtol=0.002)
            wrapper.reset()
            self.assertTrue(all(torch.count_nonzero(buffer) == 0 for _, buffer in wrapper.state_buffers()))
            # Fixed-width iOS 18 calls must not attend to or persist padding.
            for start, count in [(0, 3), (3, 4), (7, 2)]:
                real = tokens[start:start+count]
                padded = real + [63] * (4-count)
                positions = list(range(start, start+count)) + [127] * (4-count)
                actual = wrapper(torch.tensor([padded], dtype=torch.int32),
                                 torch.tensor(positions, dtype=torch.int32),
                                 torch.tensor([count], dtype=torch.int32))
                torch.testing.assert_close(actual, single[start+count-1], atol=0.002, rtol=0.002)
                for _, buffer in wrapper.state_buffers():
                    self.assertEqual(torch.count_nonzero(buffer[:, :, 127, :]), 0)


if __name__ == '__main__':
    unittest.main()
