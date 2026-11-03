#!/usr/bin/env bash
#
# Builds (1) the vendored cmark-gfm with sanitizers + coverage, then the two fuzz targets
# (libFuzzer + -standalone each), and (2) a clean, normally-flagged cmark-gfm build with its own
# test programs plus a known-answer probe over ghostwriter's Markdown layer for mayhem/test.sh.
# ghostwriter itself is a Qt/KF6 GUI app, so only its self-contained src/markdown/ layer (Qt6Core
# + cmark-gfm) is compiled here, directly, rather than through the application's CMake project.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
CMARK="$SRC/3rdparty/cmark-gfm"
QT_CFLAGS="$(pkg-config --cflags Qt6Core)"
QT_LIBS="$(pkg-config --libs Qt6Core)"
# -fsanitize=fuzzer-no-link puts SanCov instrumentation into the library, unconditionally.
FUZZ_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link"
OBJ="$SRC/build-fuzz/objs"

# 1) Sanitized + instrumented cmark-gfm (static libs only).
cmake -S "$CMARK" -B build-fuzz/cmark -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_C_FLAGS="$FUZZ_FLAGS" -DCMAKE_CXX_FLAGS="$FUZZ_FLAGS" \
      -DCMARK_TESTS=OFF -DCMARK_SHARED=OFF -DCMARK_STATIC=ON
cmake --build build-fuzz/cmark -j"$MAYHEM_JOBS" --target libcmark-gfm_static libcmark-gfm-extensions_static
CMARK_LIBS="$SRC/build-fuzz/cmark/extensions/libcmark-gfm-extensions.a $SRC/build-fuzz/cmark/src/libcmark-gfm.a"
CMARK_INC="-I$CMARK/src -I$CMARK/extensions -I$SRC/build-fuzz/cmark/src -I$SRC/build-fuzz/cmark/extensions -DCMARK_GFM_STATIC_DEFINE -DCMARK_GFM_EXTENSIONS_STATIC_DEFINE"

mkdir -p "$OBJ"
# LeakSanitizer off at build time (SPEC §6.2 item 15); ASan + UBSan stay on.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OBJ/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -x c -c "$STANDALONE_FUZZ_MAIN" -o "$OBJ/standalone_main.o"

# 2a) fuzz_cmark_gfm — the vendored parser + renderers (plain C harness).
H1="$SRC/mayhem/fuzz_cmark_gfm/fuzz_cmark_gfm.c"
$CC $FUZZ_FLAGS $CMARK_INC -c "$H1" -o "$OBJ/fuzz_cmark_gfm.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$OBJ/fuzz_cmark_gfm.o" "$OBJ/lsan_off.o" $CMARK_LIBS -o /mayhem/fuzz_cmark_gfm
$CC $SANITIZER_FLAGS $DEBUG_FLAGS "$OBJ/standalone_main.o" "$OBJ/fuzz_cmark_gfm.o" "$OBJ/lsan_off.o" $CMARK_LIBS -o /mayhem/fuzz_cmark_gfm-standalone

# 2b) fuzz_ghostwriter_markdown — ghostwriter's own src/markdown/ AST layer (Qt6Core + C++ harness).
GW_CXXFLAGS="-std=c++20 -fPIC $FUZZ_FLAGS $QT_CFLAGS -I$SRC -I$SRC/src $CMARK_INC"
GW_OBJS=""
for f in "$SRC"/src/markdown/*.cpp "$SRC/mayhem/fuzz_ghostwriter_markdown/fuzz_ghostwriter_markdown.cpp"; do
    o="$OBJ/gw_$(basename "$f" .cpp).o"
    $CXX $GW_CXXFLAGS -c "$f" -o "$o"
    GW_OBJS="$GW_OBJS $o"
done
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE $GW_OBJS "$OBJ/lsan_off.o" $CMARK_LIBS $QT_LIBS -o /mayhem/fuzz_ghostwriter_markdown
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$OBJ/standalone_main.o" $GW_OBJS "$OBJ/lsan_off.o" $CMARK_LIBS $QT_LIBS -o /mayhem/fuzz_ghostwriter_markdown-standalone

# 3) Test build with the project's NORMAL flags (no sanitizers, no DWARF pin): cmark-gfm's own
#    api_test + cmark-gfm CLI (for its spec suites) and the ghostwriter known-answer probe.
cmake -S "$CMARK" -B build-tests/cmark -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
      -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
      -DCMARK_TESTS=ON -DCMARK_SHARED=OFF -DCMARK_STATIC=ON
cmake --build build-tests/cmark -j"$MAYHEM_JOBS"
T_LIBS="$SRC/build-tests/cmark/extensions/libcmark-gfm-extensions.a $SRC/build-tests/cmark/src/libcmark-gfm.a"
T_INC="-I$CMARK/src -I$CMARK/extensions -I$SRC/build-tests/cmark/src -I$SRC/build-tests/cmark/extensions -DCMARK_GFM_STATIC_DEFINE -DCMARK_GFM_EXTENSIONS_STATIC_DEFINE"
$CXX -std=c++20 -fPIC -O1 $COVERAGE_FLAGS $QT_CFLAGS -I"$SRC" -I"$SRC/src" $T_INC \
     "$SRC/mayhem/kat/ghostwriter_kat.cpp" "$SRC"/src/markdown/*.cpp $T_LIBS $QT_LIBS -o /mayhem/ghostwriter_kat
file /mayhem/ghostwriter_kat | grep -q 'dynamically linked'
