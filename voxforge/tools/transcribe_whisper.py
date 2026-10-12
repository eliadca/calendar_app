"""OPTIONAL helper (not a VoxForge dependency): transcribe a recording, cutting at its pauses.

    pip install sherpa-onnx
    # download + unpack a sherpa-onnx whisper model (e.g. sherpa-onnx-whisper-small) from
    # https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models
    python tools/transcribe_whisper.py my_voice.wav

Prints one line per pause-delimited chunk; copy them into a TSV (start<TAB>end<TAB>text) for `voxforge clone`.
Review the text by ear: any ASR mistake becomes a mislabelled unit.
Use num_threads=1 (multi-threaded onnxruntime segfaulted in our container).
"""
import sys, numpy as np, sherpa_onnx
sys.path.insert(0, __import__('os').path.join(__import__('os').path.dirname(__file__), '..'))
from voxforge import dsp
d='sherpa-onnx-whisper-small/'
rec=sherpa_onnx.OfflineRecognizer.from_whisper(encoder=d+'small-encoder.int8.onnx',decoder=d+'small-decoder.int8.onnx',tokens=d+'small-tokens.txt',language='es',task='transcribe',num_threads=1)
x,sr=dsp.read_wav(sys.argv[1]); y=dsp.resample(x,sr,16000).astype(np.float32)
hop=160; n=len(y)//hop; r=np.sqrt((y[:n*hop].reshape(n,hop)**2).mean(1)); 
quiet=r<0.012
# pauses >= 140 ms
pauses=[]; i=0
while i<n:
    if quiet[i]:
        j=i
        while j<n and quiet[j]: j+=1
        if (j-i)>=14: pauses.append(((i+j)/2*hop/16000,(j-i)*hop/16000))
        i=j
    else: i+=1
print("pauses (center s, dur s):",[(round(a,2),round(b,2)) for a,b in pauses])
cuts=[0.0]+[p[0] for p in pauses if p[1]>=0.25]+[len(y)/16000]
# merge so every chunk is 3-14 s
merged=[cuts[0]]
for c in cuts[1:]:
    if c-merged[-1]>=3.0: merged.append(c)
if len(merged)>1 and merged[-1]!=cuts[-1]: merged[-1]=cuts[-1]
for a,b in zip(merged[:-1],merged[1:]):
    s=rec.create_stream(); s.accept_waveform(16000,np.ascontiguousarray(y[int(a*16000):int(b*16000)])); rec.decode_stream(s)
    print(f"[{a:5.2f}-{b:5.2f}s] {s.result.text.strip()}")
