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
    r-cran-rmarkdown \
    r-cran-dt

RUN apt install -y locales && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen
ENV LC_ALL en_US.UTF-8

RUN curl -Lo /tmp/bw.zip 'https://vault.bitwarden.com/download/?app=cli&platform=linux' && \
    unzip /tmp/bw.zip && \
    mv bw /usr/local/bin && \
    rm /tmp/bw.zip

COPY myteam.pl race-info.pl render.sh /srv/
COPY site /srv/site/
COPY lib /srv/lib/
WORKDIR /srv



CMD [ "./render.sh" ]
