FROM debian:jessie

MAINTAINER Thomas Toelg <docker@toelg.at>

ENV DEBIAN_FRONTEND noninteractive
ENV TERM xterm

ENV PACKAGE_VERSION_URL=http://www.mysqueezebox.com/update/?version=7.9.1&revision=1&geturl=1&os=deb
ENV LANG C.UTF-8

RUN echo Europe/Vienna >/etc/timezone && \
    ln -sf /usr/share/zoneinfo/Europe/Vienna /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata

RUN apt-get update && apt-get -y install supervisor curl wget faad flac lame sox libio-socket-ssl-perl && \
	apt-get clean && cd / && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN url=$(curl "$PACKAGE_VERSION_URL" | sed 's/_all\.deb/_amd64\.deb/') && \
	curl -Lsf -o /tmp/logitechmediaserver.deb $url && \
	dpkg -i /tmp/logitechmediaserver.deb && \
	rm -f /tmp/logitechmediaserver.deb

COPY . /

RUN chmod +x /opt/lmsprestart.sh


EXPOSE 3483 3483/udp 9000 9090

CMD ["/usr/bin/supervisord"]

