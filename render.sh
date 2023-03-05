#!/usr/bin/env bash

set -exo pipefail

./myteam.pl
./race-info.pl
R --vanilla <<_EOCMD
rmarkdown::render('pdcvds.Rmd', output_dir='out/')
_EOCMD
