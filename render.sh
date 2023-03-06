#!/usr/bin/env bash

set -exo pipefail

./myteam.pl
./race-info.pl
R --vanilla <<_EOCMD
rmarkdown::render_site("site/")
_EOCMD
