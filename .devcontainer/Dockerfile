FROM mcr.microsoft.com/devcontainers/python:3-3.14-bookworm
COPY --from=docker.io/astral/uv:latest /uv /uvx /bin/

ARG USERNAME=vscode

COPY .devcontainer/install-equinor-certificates.sh /tmp/install-equinor-certificates.sh
RUN chmod +x /tmp/install-equinor-certificates.sh \
	&& /tmp/install-equinor-certificates.sh --silent debian \
	&& rm -f /tmp/install-equinor-certificates.sh

ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

ARG DEBIAN_FRONTEND=noninteractive
ARG IC_VER=21.20.0.0.0dbru
ARG IC_DIR=instantclient_21_20
ARG IC_URL=https://download.oracle.com/otn_software/linux/instantclient/2120000/instantclient-basic-linux.x64-${IC_VER}.zip
ARG IC_SDK_URL=https://download.oracle.com/otn_software/linux/instantclient/2120000/instantclient-sdk-linux.x64-${IC_VER}.zip
ARG OTP_VERSION=27.3.4
ARG GLEAM_VERSION=1.18.1

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
	 wget \
	 curl \
	 ripgrep \
	 jq \
	 unzip \
	 docker.io \
	 rebar3 \
	 libaio1 \
	 libaio-dev \
	 build-essential \
	 autoconf \
	 m4 \
	 libncurses5-dev \
	 libssl-dev \
	 libxml2-utils \
	 xsltproc \
	 gdb \
	 valgrind \
	 strace \
	 krb5-user \
	 sssd \
	 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN wget -nv -O /tmp/instantclient.zip "${IC_URL}" \
 && unzip -o /tmp/instantclient.zip -d /opt \
 && echo "/opt/${IC_DIR}" > /etc/ld.so.conf.d/oracle-instantclient.conf \
 && ldconfig \
 && rm -f /tmp/instantclient.zip

RUN wget -nv -O /tmp/instantclient-sdk.zip "${IC_SDK_URL}" \
 && unzip -o /tmp/instantclient-sdk.zip -d /opt \
 && rm -f /tmp/instantclient-sdk.zip

RUN wget -nv -O /tmp/otp_src.tar.gz "https://github.com/erlang/otp/releases/download/OTP-${OTP_VERSION}/otp_src_${OTP_VERSION}.tar.gz" \
 && cd /tmp \
 && tar -xzf /tmp/otp_src.tar.gz \
 && cd /tmp/otp_src_${OTP_VERSION} \
 && ./configure --prefix=/usr/local/otp-${OTP_VERSION} --without-javac --without-odbc --without-wx --enable-kernel-poll \
 && make -j"$(nproc)" \
 && make install \
 && ln -sfn /usr/local/otp-${OTP_VERSION} /usr/local/otp \
 && rm -rf /tmp/otp_src.tar.gz /tmp/otp_src_${OTP_VERSION}

RUN wget -nv -O /tmp/gleam.tar.gz "https://github.com/gleam-lang/gleam/releases/download/v${GLEAM_VERSION}/gleam-v${GLEAM_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
 && tar -xzf /tmp/gleam.tar.gz -C /tmp \
 && install -m 0755 /tmp/gleam /usr/local/bin/gleam \
 && rm -f /tmp/gleam /tmp/gleam.tar.gz

ENV ORACLE_IC_DIR=/opt/${IC_DIR}
ENV OTP_ROOT=/usr/local/otp
# Old Linuxbrew path (disabled):
# ENV PATH=${PATH}:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin
ENV PATH=${OTP_ROOT}/bin:${PATH}

RUN printf '%s\n' \
	'# Source-built OTP toolchain takes precedence in interactive shells' \
	'export OTP_ROOT=/usr/local/otp' \
	'export PATH=/home/vscode/.local/bin:${OTP_ROOT}/bin:${PATH}' \
	> /etc/profile.d/otp-source-path.sh

USER ${USERNAME}
ENV NONINTERACTIVE=1