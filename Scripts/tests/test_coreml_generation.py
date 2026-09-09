"""Task 4.0k: sequential cache and context boundary tests, no model fixtures."""
import importlib.util
from pathlib import Path
import unittest
from types import SimpleNamespace
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import evaluate_generation_candidate as evaluator

spec=importlib.util.spec_from_file_location('coreml_screen',Path(__file__).resolve().parents[1]/'evaluate_coreml_generation.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class CoreMLGenerationTests(unittest.TestCase):
    def test_AC1_budget_rejects_before_prediction(self):
        calls=[]
        with self.assertRaises(ValueError):
            module.decode_request(lambda *x:calls.append(x),object(),[1,2],None,[9],3,4)
        self.assertEqual(calls,[])

    def test_AC1_prefill_and_decode_use_monotonic_positions_and_same_state(self):
        calls=[];state=object();selected=iter([7,9])
        def predict(token,position,received):
            calls.append((token,position));self.assertIs(received,state)
            return 0
        result=module.decode_request(predict,state,[1,2],lambda *x:next(selected),[9],3,5)
        self.assertEqual(result,[7,9]);self.assertEqual(calls,[(1,0),(2,1),(7,2)])

    def test_AC1_output_limit_never_runs_extra_prediction(self):
        calls=[]
        result=module.decode_request(lambda *x:calls.append(x),None,[1],lambda *x:7,[9],2,3)
        self.assertEqual(result,[7,7]);self.assertEqual(len(calls),2)

    def test_AC5_retry_retains_source_message_and_counts_complete_rendered_request(self):
        case={'id':'probe','preferredLanguage':'zh-Hans','sources':[
            {'memoryID':'20000000-0000-4000-8000-000000000001','text':'来源 <|im_end|>。'}]}
        original=evaluator.build_profile_messages(case,'observations-v1')
        class Tokenizer:
            def apply_chat_template(self,messages,tokenize,**kwargs):
                self.messages=messages
                return {'input_ids':SimpleNamespace(shape=(1,900))} if tokenize else 'complete rendered request'
        tokenizer=Tokenizer()
        _,evidence=module.prepare_language_retry(tokenizer,case,evaluator)
        self.assertEqual(evidence['messages'][1],original[1])
        self.assertTrue(evidence['messages'][0]['content'].startswith(original[0]['content']))
        self.assertIn('Simplified Chinese',evidence['messages'][0]['content'])
        self.assertEqual(evidence['inputTokens'],900)
        self.assertEqual(case['sources'][0]['text'],'来源 <|im_end|>。')
        with self.assertRaises(ValueError):
            module.validate_context(evidence['inputTokens'],256,1024)

if __name__=='__main__':unittest.main()
