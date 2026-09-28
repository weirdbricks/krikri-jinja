abs_spec_bin := justfile_directory() + "/.crystal-build-cache/spec_bin"

# Run the spec suite in parallel across up to 4 real OS threads.
#
# minitest.cr's --parallel needs Crystal's multi-thread scheduler
# (-Dpreview_mt) to actually use more than one core - without it,
# --parallel just interleaves fibers on one thread and buys nothing.
# Engine/Context are RWLock/Mutex-guarded for exactly this (see
# src/krikri_jinja/evaluator.cr, src/krikri_jinja/context.cr); anything
# that adds a new module-level mutable singleton needs the same care,
# and any spec exercising one needs the same serialization as
# spec/krikri_jinja/default_engine_spec.cr.
test: build-spec
    CRYSTAL_WORKERS=4 {{abs_spec_bin}} --parallel 4

# Single-threaded run (no -Dpreview_mt) - use this to bisect whether a
# failure is a real bug or a parallel-run race like the one above.
test-serial:
    crystal spec

build-spec:
    mkdir -p .crystal-build-cache
    crystal build -Dpreview_mt spec/krikri_jinja/*.cr -o {{abs_spec_bin}}

# Differential test vs real Jinja2 (140+ cases); exits nonzero on divergence.
compare:
    ./compare/run.sh
