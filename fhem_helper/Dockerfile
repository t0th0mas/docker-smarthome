FROM debian:jessie

MAINTAINER Thomas Toelg <docker@toelg.at>

ENV DEBIAN_FRONTEND noninteractive
ENV TERM xterm

RUN echo Europe/Vienna >/etc/timezone && \
	ln -sf /usr/share/zoneinfo/Europe/Vienna /etc/localtime && \
	dpkg-reconfigure -f noninteractive tzdata

RUN apt-get update && apt-get -y install \
	bluez \
	bluez-hcidump \
	build-essential \
	gcc \
	git-core \
	libnet-server-perl \
	libusb-1.0-0-dev \
	make \
	perl \
	supervisor \
	ser2net \
	wget && \
	apt-get clean && cd / && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR "/opt"

RUN mkdir -p /var/log/supervisor && \
	wget https://github.com/mhop/fhem-mirror/raw/master/fhem/contrib/PRESENCE/presenced && \
	chmod +x presenced && \
	chgrp -cR dialout presenced && \
	wget https://github.com/mhop/fhem-mirror/raw/master/fhem/contrib/PRESENCE/lepresenced && \
	chmod +x lepresenced && \
	chgrp -cR dialout lepresenced && \
	git clone git://git.zerfleddert.de/hmcfgusb && \
	cd hmcfgusb && \
	make && \
	chmod +x hmland

WORKDIR "/opt"


# hmland, lepresenced, presenced
EXPOSE 5111 5333 5444

COPY . /
CMD ["/usr/bin/supervisord"]
