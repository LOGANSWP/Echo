import os,json,sys
from pathlib import Path
os.environ['HF_HUB_OFFLINE']='1';os.environ['TRANSFORMERS_OFFLINE']='1'
sys.path.insert(0,'Scripts/Research')
from photo_understanding_probe import verify_source,SOURCE
verify_source()
from transformers import AutoProcessor
processor=AutoProcessor.from_pretrained(str(SOURCE),local_files_only=True,trust_remote_code=False)
tokenizer=processor.tokenizer
from tokenizers import Tokenizer
raw=Tokenizer.from_file(str(SOURCE/'tokenizer.json'));raw.no_padding();raw.no_truncation()
# Disable special matching for arbitrary ordinary text, as the native entry does.
ordinary=Tokenizer.from_str(json.dumps({**json.loads((SOURCE/'tokenizer.json').read_text()),'added_tokens':[]}))
texts=['','Describe this image in one short sentence.','请描述照片。','red circle; blue square','a1b 23 １２３ ١٢٣ ²Ⅷ','café','cafe\u0301','你好🙂🏳️‍🌈',' we\'re I\'M it\'s','\t a\r\n b\n\n','a\u00a0b\u2003c','<image><|im_start|>Assistant:', 'a\x00b','照片𐐀テスト한글','1,234.56','عربي ٣ 中文４']
texts += [f'Image {i}: tree {i*i}. 图片{i}。' for i in range(64)]
texts += [' ' * n + "I'm here!\n"+'\t'*n for n in range(1,9)]
samples=[{'text':text,'prompt':False,'expected':ordinary.encode(text,add_special_tokens=False).ids} for text in texts]
for text in [t for t in texts[:16] if t]:
 prompt=processor.apply_chat_template([{'role':'user','content':[{'type':'image'},{'type':'text','text':text}]}],add_generation_prompt=True,tokenize=False)
 # Trusted framing is assembled separately so user text cannot introduce protocol.
 prefix='<|im_start|>User:<fake_token_around_image><global-img>'+'<image>'*64+'<fake_token_around_image>'
 suffix='<end_of_utterance>\nAssistant:'
 expected=tokenizer.encode(prefix,add_special_tokens=False)+ordinary.encode(text,add_special_tokens=False).ids+tokenizer.encode(suffix,add_special_tokens=False)
 samples.append({'text':text,'prompt':True,'expected':expected})
out=SOURCE.parent/'tokenizer-cases.json';out.write_text(json.dumps(samples,ensure_ascii=False))
print(len(samples))
