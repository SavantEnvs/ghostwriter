# cmark-gfm autolink `validate_protocol` read underflow

`crash-seed` triggers a halting UBSan `pointer-overflow` report at `autolink.c:282` (the negative index is applied as an unsigned `size_t`); with that check relaxed ASan reports a heap-buffer-overflow READ underflow at `autolink.c:277/282`, in the vendored `3rdparty/cmark-gfm`
(`extensions/autolink.c`, `validate_protocol`, called from `postprocess_text`).

- Cause: `validate_protocol` reads `data[-rewind - i]` and `data[-rewind - len - 1]` without checking that
  the text node holds that many bytes before the `:` of a possible `www.`/`http://`-style autolink, so a
  short text node that starts with `:` / `//` reads before the start of the buffer.
- Impact: out-of-bounds read of up to `strlen(protocol)+1` bytes before a heap buffer.
- Fix (upstream): bound the loop by the available prefix (`rewind` plus the bytes before `data` within the
  node) before indexing, and return false when the prefix is shorter than the protocol.
- It is deliberately NOT in `testsuite/`: a seed that crashes would abort every corpus replay. Mayhem
  rediscovers it from the autolink extension on its own; the standalone binary reproduces it:
  `/mayhem/<target>-standalone mayhem/<target>/known-findings/autolink-validate-protocol-underread/crash-seed`.
