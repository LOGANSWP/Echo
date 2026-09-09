"""Task 4.0k: synthetic Qwen3 graph parity, not candidate-quality evidence."""
import importlib.util
import os
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("generation_converter", ROOT / "Scripts/convert_generation_candidate.py")
converter = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(converter)


class GenerationConversionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ.update({"HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1",
                           "HF_HUB_DISABLE_TELEMETRY": "1", "DO_NOT_TRACK": "1"})
        import torch
        from transformers import Qwen3Config, Qwen3ForCausalLM
        cls.torch = torch
        torch.set_num_threads(2)
        torch.manual_seed(4)
        # Deliberately make Q * head_dim differ from hidden_size, as in Qwen3-0.6B.
        config = Qwen3Config(hidden_size=32, num_attention_heads=4, num_key_value_heads=2,
                            head_dim=16, intermediate_size=64, num_hidden_layers=2,
                            vocab_size=64, max_position_embeddings=128, attention_bias=False)
        config._attn_implementation = "eager"
        cls.official = Qwen3ForCausalLM(config).eval()

    def test_AC1_qk_norm_head_width_and_stateful_prefix_match_official_graph(self):
        torch = self.torch
        wrapper = converter.build_wrapper(self.official)
        with torch.inference_mode():
            for position, token in enumerate([4, 9, 2]):
                actual = wrapper(torch.tensor([[token]], dtype=torch.int32),
                                 torch.tensor([position], dtype=torch.int32)).numpy()
                expected = self.official(torch.tensor([[4, 9, 2][:position + 1]]),
                                         use_cache=False).logits[:, -1, :].numpy()
                result = converter.metrics(actual, expected, converter.LIMITS["torch_vs_official"])
                self.assertTrue(result["passed"], result)

    def test_AC1_reset_erases_all_request_cache_buffers(self):
        torch = self.torch
        wrapper = converter.build_wrapper(self.official)
        buffers = wrapper.state_buffers()
        self.assertEqual(len(buffers), 4)
        self.assertTrue(all(tuple(buffer.shape) == (1, 2, 128, 16) for _, buffer in buffers))
        with torch.inference_mode():
            wrapper(torch.tensor([[4]], dtype=torch.int32), torch.tensor([0], dtype=torch.int32))
            self.assertTrue(any(torch.count_nonzero(buffer) for _, buffer in buffers))
            wrapper.reset()
            self.assertTrue(all(torch.count_nonzero(buffer) == 0 for _, buffer in buffers))


if __name__ == "__main__":
    unittest.main()
