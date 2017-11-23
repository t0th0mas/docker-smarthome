#!/bin/sh

if [ "/opt/squeezebox" ] && [ -d "/opt/squeezebox" ]; then
	for subdir in prefs logs cache; do
		mkdir -p /opt/squeezebox/$subdir
		chown -R squeezeboxserver:nogroup /opt/squeezebox/$subdir
	done
fi
