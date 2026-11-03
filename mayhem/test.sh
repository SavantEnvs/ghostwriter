#!/usr/bin/env bash
#
# mayhem/test.sh — RUNS the suites mayhem/build.sh built: cmark-gfm's own CommonMark/GFM spec suites and
# api_test (against the vendored library ghostwriter renders with) plus known-answer probes that run
# ghostwriter's own src/markdown/ layer on a fixed document and assert exact AST/HTML output.
#
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}


export PYTHONWARNINGS=ignore
CMARK="$SRC/3rdparty/cmark-gfm"
CLI="$SRC/build-tests/cmark/src/cmark-gfm"
KAT="$SRC/mayhem/kat"
passed=0 ; failed=0

for bin in "$CLI" "$SRC/build-tests/cmark/api_test/api_test" /mayhem/ghostwriter_kat; do
  [ -x "$bin" ] || { echo "missing test binary $bin — build.sh should have produced it" >&2; failed=$((failed+1)); }
done

# Spec suites: parse spec_tests.py's own "<P> passed, <F> failed, <E> errored, <S> skipped" summary.
# A neutered cmark-gfm prints nothing, every example fails, and the summary shows it.
run_spec() {
  local name="$1" spec="$2" program="$3" extensions="${4:-}" want="$5" out p f e
  if [ -n "$extensions" ]; then
    out="$(python3 "$CMARK/test/spec_tests.py" --no-normalize --spec "$spec" --program "$program" --extensions "$extensions" 2>&1)"
  else
    out="$(python3 "$CMARK/test/spec_tests.py" --no-normalize --spec "$spec" --program "$program" 2>&1)"
  fi
  echo "$name: $(printf '%s\n' "$out" | tail -1)"
  if [[ "$(printf '%s\n' "$out" | tail -1)" =~ ^([0-9]+)\ passed,\ ([0-9]+)\ failed,\ ([0-9]+)\ errored ]]; then
    p=${BASH_REMATCH[1]} ; f=$(( BASH_REMATCH[2] + BASH_REMATCH[3] ))
  else
    p=0 ; f=1
  fi
  # Pin the expected example count so a suite that silently ran nothing cannot pass.
  [ "$p" -ge "$want" ] || f=$((f+1))
  passed=$((passed+p)) ; failed=$((failed+f))
}
run_spec commonmark-spec    "$CMARK/test/spec.txt"         "$CLI"           ""  600
run_spec smart-punctuation  "$CMARK/test/smart_punct.txt"  "$CLI --smart"   ""  16
run_spec gfm-extensions     "$CMARK/test/extensions.txt"   "$CLI"           "table strikethrough autolink tagfilter footnotes tasklist" 30

# cmark-gfm's C API test program: "<N> tests passed, <F> failed, <S> skipped".
api_out="$("$SRC/build-tests/cmark/api_test/api_test" 2>&1)"
echo "api_test: $(printf '%s\n' "$api_out" | tail -2 | head -1)"
if [[ "$api_out" =~ ([0-9]+)\ tests\ passed,\ ([0-9]+)\ failed ]] && [ "${BASH_REMATCH[1]}" -ge 500 ]; then
  passed=$((passed+BASH_REMATCH[1])) ; failed=$((failed+BASH_REMATCH[2]))
else
  failed=$((failed+1))
fi

# Known-answer probes: ghostwriter's CmarkGfmAPI/MarkdownAST/MarkdownNode on mayhem/kat/sample.md.
kat_out="$(/mayhem/ghostwriter_kat "$KAT/sample.md" 2>&1)"
expect_line() {
  if printf '%s\n' "$kat_out" | grep -qxF -- "$1"; then passed=$((passed+1)); else echo "KAT FAIL: missing line: $1" >&2; failed=$((failed+1)); fi
}
expect_line 'HEADING level=1 line=1 atx=1 setext=0'
expect_line 'HEADING level=2 line=5 atx=0 setext=1'
expect_line '<h1>Ghostwriter</h1>'
expect_line '<p>Hello <em>world</em> and <strong>bold</strong> with <del>gone</del> text.</p>'
expect_line '<li><input type="checkbox" checked="" disabled="" /> done task</li>'
expect_line '<th>a</th>'
expect_line '<td>2</td>'
expect_line '<pre><code class="language-c">int x;'
expect_line '   ->> [lines 1 - 1][col 0, len 13, indent 0, in break false] Heading -> Ghostwriter...'
expect_line '      ->> [lines 3 - 3][col 32, len 8, indent 0, in break false] Strikethrough -> ...'
expect_line '   ->> [lines 11 - 13][col 0, len 9, indent 0, in break false] Table -> ...'
expect_line 'BLOCK-AT-5 > [lines 5 - 7][col 0, len 0, indent 0, in break false] Heading -> Setext Heading...'
[ "$(printf '%s\n' "$kat_out" | grep -c 'Text ->')" = "15" ] && passed=$((passed+1)) || { echo "KAT FAIL: expected 15 Text nodes" >&2; failed=$((failed+1)); }

emit_ctrf "cmark-gfm-spec+ghostwriter-kat" "$passed" "$failed" 0
