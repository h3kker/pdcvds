FROM perl:5.36

RUN cpanm -i Mojolicious \
    DateTime \
    Moose

RUN apt update && \
    apt install --no-install-recommends -y \
    r-cran-dplyr \
    r-cran-jsonlite \
    r-cran-lubridate \
    r-cran-ggplot2 \
    r-cran-rmarkdown

COPY team.json race-info.pl pdcvds.Rmd render.sh /srv/
COPY lib /srv/lib/
WORKDIR /srv

CMD [ "./render.sh" ]