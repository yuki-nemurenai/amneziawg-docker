ARG GOLANG_VERSION=1.25.3
ARG ALPINE_VERSION=3.22
FROM golang:${GOLANG_VERSION}-alpine${ALPINE_VERSION} AS builder

ARG TARGETOS TARGETARCH TARGETVARIANT

RUN apk update \
    && apk add --no-cache \
    git \
    make \
    bash \
    build-base \
    linux-headers

RUN git clone https://github.com/amnezia-vpn/amneziawg-tools.git \
    && git clone https://github.com/amnezia-vpn/amneziawg-go.git

RUN cd amneziawg-tools/src \
    && GOOS=${TARGETOS} GOARCH=${TARGETARCH} GOARM=${TARGETVARIANT} make

RUN cd amneziawg-go \
    && GOOS=${TARGETOS} GOARCH=${TARGETARCH} GOARM=${TARGETVARIANT} make

FROM alpine:${ALPINE_VERSION}

RUN apk update \
    && apk add --no-cache \
    bash \
    openrc \
    iptables \
    iptables-legacy \
    iproute2 \
    openresolv \
    && apk upgrade --no-cache \
    && rm -rf /var/cache/apk/* /tmp/* /var/tmp/* /var/log/*

COPY --from=builder /go/amneziawg-go/amneziawg-go /usr/bin/amneziawg-go
COPY --from=builder /go/amneziawg-tools/src/wg-quick/awg /usr/bin/awg
COPY --from=builder /go/amneziawg-tools/src/wg-quick/linux.bash /usr/bin/awg-quick
COPY wireguard-fs /

RUN \
    sed -i 's/^\(tty\d\:\:\)/#\1/' /etc/inittab && \
    sed -i \
        -e 's/^#\?rc_env_allow=.*/rc_env_allow="\*"/' \
        -e 's/^#\?rc_sys=.*/rc_sys="docker"/' \
        /etc/rc.conf && \
    sed -i \
        -e 's/VSERVER/DOCKER/' \
        -e 's/checkpath -d "$RC_SVCDIR"/mkdir "$RC_SVCDIR"/' \
        /usr/libexec/rc/sh/init.sh && \
    rm \
        /etc/init.d/hwdrivers \
        /etc/init.d/machine-id

RUN sed -i 's/cmd sysctl -q \(.*\?\)=\(.*\)/[[ "$(sysctl -n \1)" != "\2" ]] \&\& \0/' /usr/bin/awg-quick

RUN  rm -f /usr/sbin/iptables && \
     rm -f /usr/sbin/ip6tables && \
     ln -sf /usr/sbin/iptables-legacy /usr/sbin/iptables && \
     ln -sf /usr/sbin/iptables-legacy-save /usr/sbin/iptables-save && \
     ln -sf /usr/sbin/iptables-legacy-restore /usr/sbin/iptables-restore && \
     ln -sf /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables && \
     ln -sf /usr/sbin/ip6tables-legacy-save /usr/sbin/ip6tables-save && \
     ln -sf /usr/sbin/ip6tables-legacy-restore /usr/sbin/ip6tables-restore

RUN echo "200 awg" > /etc/iproute2/rt_tables && \
    chmod 644 /etc/iproute2/rt_tables && \
    cat /etc/iproute2/rt_tables

# register /etc/init.d/wg-quick
RUN rc-update add wg-quick default

VOLUME ["/sys/fs/cgroup"]
HEALTHCHECK --interval=15m --timeout=30s CMD /bin/bash /data/healthcheck.sh
CMD ["/sbin/init"]
