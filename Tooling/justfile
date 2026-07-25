set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# Public Runtime API — thin wrappers only.

doctor *args:
    ./Tooling/scripts/doctor.sh {{args}}

env:
    ./Tooling/scripts/env.sh

diagnose:
    ./Tooling/scripts/diagnose.sh

format:
    ./Tooling/scripts/format.sh

lint:
    ./Tooling/scripts/lint.sh

build:
    ./Tooling/scripts/build.sh

test:
    ./Tooling/scripts/test.sh

verify:
    ./Tooling/scripts/verify.sh

ci:
    ./Tooling/scripts/ci.sh

clean:
    ./Tooling/scripts/clean.sh

reset:
    ./Tooling/scripts/reset.sh

release:
    ./Tooling/scripts/release.sh

profile:
    ./Tooling/scripts/profile.sh

harness-update:
    ./Tooling/scripts/harness-update.sh
