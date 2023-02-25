#!/usr/bin/env bash

set -exo pipefail

./race-info.pl
R --vanilla <<_EOCMD
rmarkdown::render('pdcvds.Rmd', output_dir='out/')
_EOCMD