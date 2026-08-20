# ARTEMIS Installation on Locked-Down Server (Python 3.10)

ARTEMIS v1.3.0+ requires Python 3.12, but the actual Python code (numpy/pandas
alignment) works fine on 3.10. On a locked-down server without access to pyenv
or direct Python downloads, install from a patched local clone.

## Prerequisites

- R 4.4+ with `reticulate` installed
- Python 3.10+ with `pip` access to PyPI
- Git access to GitHub

## Steps

```bash
# 1. Clone ARTEMIS
cd /tmp
git clone https://github.com/OHDSI/ARTEMIS.git

# 2. Patch the Python version gate (3.12 -> 3.10)
sed -i 's/ver_minor < 12/ver_minor < 10/' /tmp/ARTEMIS/R/zzz.R
```

```r
# 3. Install R dependencies first (if not already present)
install.packages(c("reticulate", "patchwork"))
# patchwork requires ggplot2 >= 3.5; if ggplot2 is too old:
#   options(timeout = 300)  # large package, default 60s may timeout
#   install.packages("ggplot2")

# 4. Install ARTEMIS from the patched local clone
install.packages("/tmp/ARTEMIS", repos = NULL, type = "source")

# 5. Verify
library(ARTEMIS)
```

ARTEMIS's `.onLoad` will create a Python virtualenv inside the installed
package directory and install `numpy` and `pandas` via pip on first load.

## Why this works

The Python 3.12 gate in `R/zzz.R` is a conservative version check — the
alignment code uses only numpy and pandas, which are compatible with Python
3.10. All ARTEMIS R functions (`loadDrugs`, `loadRegimens`,
`stringDF_from_cdm`, `generateRawAlignments`, `processAlignments`,
`plotAlignment`) work unchanged.

## Version note

An older ARTEMIS (v1.2.0) has no Python 3.12 requirement, but its API is
incompatible with this study's vendored code (different `loadRegimens` and
`processAlignments` signatures, no `plotAlignment` export). v1.3.0 is the
earliest version with the correct API.
