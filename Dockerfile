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

RUN apt install -y locales && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen
ENV LC_ALL en_US.UTF-8

COPY team.json race-info.pl pdcvds.Rmd render.sh /srv/
COPY lib /srv/lib/
WORKDIR /srv



CMD [ "./render.sh" ]