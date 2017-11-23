FROM debian:jessie

MAINTAINER Thomas Toelg <docker@toelg.at>

ENV DEBIAN_FRONTEND noninteractive
ENV TERM xterm

RUN echo Europe/Vienna >/etc/timezone && \
	ln -sf /usr/share/zoneinfo/Europe/Vienna /etc/localtime && \
	dpkg-reconfigure -f noninteractive tzdata

RUN apt-get update && apt-get -y install supervisor wget apt-transport-https && \
	wget -qO - https://debian.fhem.de/archive.key | apt-key add - && \
	echo "deb http://debian.fhem.de/nightly/ /" | tee -a /etc/apt/sources.list.d/fhem.list && \
	apt-get update && apt-get -y --force-yes install fhem supervisor make gcc-avr avrdude avr-libc subversion unzip usbutils libcrypt-rijndael-perl libxml-simple-perl && \
	apt-get clean && cd / && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN pkill -f "perl fhem.pl fhem.cfg" && \
	update-rc.d fhem disable && \
	chown -R root:root /opt/fhem/ && \
	userdel fhem

COPY . /
COPY ./opt/fhem/FHEM/*.pm /tmp/

WORKDIR "/opt/fhem"

RUN exclude_from_update=$(ls /tmp/*_*.pm | sed -r 's/^.+\///' | xargs) && \
	sed -i "s|%exclude_from_update%|$exclude_from_update|" fhem.cfg.update && \
	rm /tmp/*_*.pm

RUN perl fhem.pl fhem.cfg.update | tee /opt/fhem/log/fhem.log && \
	rm /opt/fhem/log/* && \
	rm -R /opt/fhem/restoreDir && \
	rm /opt/fhem/fhem.cfg && \
	rm /opt/fhem/FHEM/template.layout


EXPOSE 8083

CMD ["/usr/bin/supervisord"]

