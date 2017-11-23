FROM openjdk:8-jre

MAINTAINER Thomas Toelg <docker@toelg.at>

ENV DEBIAN_FRONTEND noninteractive
ENV TERM xterm

RUN echo Europe/Vienna >/etc/timezone && \
	ln -sf /usr/share/zoneinfo/Europe/Vienna /etc/localtime && \
	dpkg-reconfigure -f noninteractive tzdata

RUN apt-get update && apt-get -y install supervisor && \
	apt-get clean && cd / && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mkdir -p /opt/habridge/data && cd /opt/habridge && \
	VERSION="$(curl -s https://api.github.com/repos/bwssytems/ha-bridge/releases/latest | grep browser_download_url | cut -d '"' -f 4)" && \
	wget $VERSION && \
	mv ha-bridge-*.jar ha-bridge.jar && \
	chown -R nobody:users /opt/habridge

COPY . /

EXPOSE 8000 50000

CMD ["/usr/bin/supervisord"]
