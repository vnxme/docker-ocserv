ARG ALPINE_VERSION=3.23.0

FROM alpine:${ALPINE_VERSION}

ENV OC_VERSION=1.3.0

RUN buildDeps=" \
		curl \
		g++ \
		gnutls-dev \
		gpgme \
		libev-dev \
		libnl3-dev \
		libseccomp-dev \
		linux-headers \
		linux-pam-dev \
		lz4-dev \
		make \
		readline-dev \
		tar \
		xz \
	"; echo "${buildDeps}" \
	&& set -x \
	&& apk add --update --no-cache --purge --clean-protected --virtual .build-deps ${buildDeps} \
	&& curl -SL "ftp://ftp.infradead.org/pub/ocserv/ocserv-${OC_VERSION}.tar.xz" -o ocserv.tar.xz \
	&& mkdir -p /usr/src/ocserv \
	&& tar -xf ocserv.tar.xz -C /usr/src/ocserv --strip-components=1 \
	&& rm ocserv.tar.xz* \
	&& cd /usr/src/ocserv \
	&& ./configure \
	&& make -j"$(nproc)" \
	&& make install \
	&& mkdir -p /etc/ocserv \
	&& cp /usr/src/ocserv/doc/profile.xml /etc/ocserv/profile.xml \
	&& cp /usr/src/ocserv/doc/sample.config /etc/ocserv/ocserv.conf \
	&& rm -rf /usr/src/ocserv \
	&& runDeps="$( \
		(scanelf --needed --nobanner /usr/local/bin/occtl; \
		scanelf --needed --nobanner /usr/local/bin/ocpasswd; \
		scanelf --needed --nobanner /usr/libexec/ocserv-fw; \
		scanelf --needed --nobanner /usr/local/sbin/ocserv; \
		scanelf --needed --nobanner /usr/local/sbin/ocserv-worker) \
			| awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
			| xargs -r apk info --installed \
			| sort -u \
		)"; echo "${runDeps}" \
	&& apk del --purge .build-deps \
	&& apk add --no-cache --purge --clean-protected --virtual .run-deps ${runDeps} \
	&& runExtras=" \
		curl \
		iproute2 \
		iptables \
		iptables-legacy \
		iputils-ping \
		libcap \
		net-tools \
		openssl \
		vlan \
	"; echo "${runExtras}"\
	&& apk add --no-cache --purge --clean-protected --virtual .run-extras ${runExtras} \
	&& mkdir -p /app/hooks/up /app/hooks/down

COPY entrypoint.sh /app/
RUN chmod 755 /app/*.sh

WORKDIR /app

EXPOSE 443
EXPOSE 443/udp

CMD []
ENTRYPOINT ["/app/entrypoint.sh"]
