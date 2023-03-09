FROM perl:5.36

RUN apt update && \
    apt install -y locales && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen
ENV LC_ALL en_US.UTF-8

RUN curl -Lo /tmp/bw.zip 'https://vault.bitwarden.com/download/?app=cli&platform=linux' && \
    unzip /tmp/bw.zip && \
    mv bw /usr/local/bin && \
    rm /tmp/bw.zip

RUN cpanm --notest -i Mojolicious \
    DateTime \
    DateTime::Format::Strptime \
    Moose && \
    rm -rf ~/.cpanm

RUN apt update && \
    apt install --no-install-recommends -y \
    r-cran-dplyr \
    r-cran-jsonlite \
    r-cran-lubridate \
    r-cran-ggplot2 \
    r-cran-rmarkdown \
    r-cran-dt \
    r-cran-tidyr \
    r-cran-stringr

COPY myteam.pl race-info.pl render.sh watch.json /srv/
COPY site /srv/site/
COPY lib /srv/lib/
WORKDIR /srv

CMD [ "./render.sh" ]
