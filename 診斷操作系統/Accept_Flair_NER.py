"""Close the last SKIP: actually run flair NER, which needs a model download.
Model cache goes to ~/.flair (NOT under AppData, so the MSIX container does not
redirect it)."""
import os, sys
os.environ.setdefault('HF_HUB_DISABLE_SYMLINKS_WARNING', '1')
from flair.data import Sentence
from flair.nn import Classifier

print('cache dir:', os.path.join(os.path.expanduser('~'), '.flair'))
tagger = Classifier.load('ner-fast')
s = Sentence('Taipei is the capital of Taiwan and Lei Ou works in Kuala Lumpur .')
tagger.predict(s)
ents = [(e.text, e.get_label('ner').value, round(e.get_label('ner').score, 3))
        for e in s.get_spans('ner')]
print('entities:', ents)
ok = any(t == 'LOC' for _, t, _ in ents)
print('RESULT:', 'PASS' if ok else 'FAIL')
sys.exit(0 if ok else 1)
