# syntax=docker/dockerfile:1

ARG IMAGE_BASE="ghcr.io/actions/actions-runner:latest"
ARG WINE_BRANCH="stable"
ARG WINE_VERSION="11.0"
ARG MSVC_VERSION="17.8"
ARG WIN_SDK_VERSION="10.0.22621"

# Building wine from source with the oleaut32 typelib patch to properly compile with the VS typelib for opening blueprint nodes in VS
# until https://gitlab.winehq.org/wine/wine/-/merge_requests/9640 is merged
FROM $IMAGE_BASE AS wine-builder

ARG WINE_BRANCH
ARG WINE_VERSION
ARG BUILD_JOBS=16

RUN sudo apt update && \
    sudo apt install -y --no-install-recommends build-essential wget curl ca-certificates devscripts debhelper fakeroot

RUN sudo mkdir -pm755 /etc/apt/keyrings && \
    wget -O - https://dl.winehq.org/wine-builds/winehq.key | sudo gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key - && \
    sudo wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/$(lsb_release -cs)/winehq-$(lsb_release -cs).sources && \
    sudo sed -Ei 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/winehq-$(lsb_release -cs).sources && \
    sudo apt update && \
    sudo apt build-dep -y winehq-$WINE_BRANCH

RUN sudo mkdir -p /build/wine && sudo chown runner:docker /build/wine && cd /build/wine && \
    wget -O wine_typelib.patch https://gitlab.winehq.org/wine/wine/-/merge_requests/9640.patch && \
    apt source winehq-$WINE_BRANCH=$WINE_VERSION && \
    cd wine-* && \
    # Use WoW64, even though not "officially" supported by wine on ubuntu 24.04
    sed -i 's/--enable-win64/--enable-archs=i386,x86_64/' debian/rules && \
    echo /opt/wine-$WINE_BRANCH/lib/wine/i386-windows >> debian/wine-$WINE_BRANCH-amd64.install && \
    rm debian/wine-$WINE_BRANCH-i386.install && \
    sed -i "/^Package: wine-$WINE_BRANCH-i386\$/,/^\$/d; /wine-$WINE_BRANCH-i386/d" debian/control && \
    sed -i 's/^Build-Depends: /Build-Depends: gcc-mingw-w64-i686, gcc-mingw-w64-x86-64, /' debian/control && \
    sudo apt build-dep -y . && \
    patch -p1 < ../wine_typelib.patch && \
    DEBEMAIL="ci@example.com" DEBFULLNAME="CI" \
    dch --local +patched --distribution $(lsb_release -cs) "Applied typelib patch" && \
    DEB_BUILD_OPTIONS="nocheck nodoc parallel=${BUILD_JOBS}" dpkg-buildpackage -b -uc -us

FROM $IMAGE_BASE

ENV RUNNER_TOOL_CACHE="/opt/hostedtoolcache"

RUN sudo mkdir -p $RUNNER_TOOL_CACHE && sudo chown runner:docker $RUNNER_TOOL_CACHE

# Wine build dependencies, msvc-wine dependencies, archiving dependencies
RUN sudo apt update && \
    sudo apt install -y --no-install-recommends \
        wget msitools perl xvfb && \
    sudo rm -rf /var/lib/apt/lists/*

# Github CLI
RUN  (type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
        && sudo mkdir -p -m 755 /etc/apt/keyrings \
        && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
        && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        && sudo mkdir -p -m 755 /etc/apt/sources.list.d \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
        && sudo apt update \
        && sudo apt install gh -y \
        && sudo rm -rf /var/lib/apt/lists/* \
        && rm -f $out

# Wine
ARG WINE_BRANCH
ARG WINE_VERSION

# TODO: install upstream wine when the typelib PR is merged
RUN --mount=from=wine-builder,target=/tmp/wine-build \
    sudo mkdir -pm755 /etc/apt/keyrings && \
    wget -O - https://dl.winehq.org/wine-builds/winehq.key | sudo gpg --dearmor -o /etc/apt/keyrings/winehq-archive.key - && \
    sudo wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/$(lsb_release -cs)/winehq-$(lsb_release -cs).sources && \
    sudo apt update && \
    cd /tmp/wine-build/build/wine && \
    sudo apt install -y --no-install-recommends ./wine*-${WINE_BRANCH}_*.deb ./wine*-${WINE_BRANCH}-amd64_*.deb && \
    sudo rm -rf /var/lib/apt/lists/*

ENV WINEPREFIX=/opt/wineprefix
ENV WINEDEBUG=-all
RUN sudo mkdir -p /opt/wineprefix && sudo chown runner:docker /opt/wineprefix && \
    WINEDLLOVERRIDES="mscoree,mshtml=" xvfb-run -a wineboot -u && \
    wineserver -w

# MSVC
ARG MSVC_VERSION
ARG WIN_SDK_VERSION

COPY --chown=runner:docker --chmod=755 <<"EOF" /tmp/pdbcopy
#!/usr/bin/env bash

. "$(dirname "$0")"/msvcenv.sh

SDKDEBUGBINDIR="$SDKBASE/Debuggers/x64"
"$(dirname "$0")"/wine-msvc.sh "$SDKDEBUGBINDIR/pdbcopy.exe" "$@"
EOF

RUN cd /tmp && \
    git clone -b ue-patches https://github.com/mircearoata/msvc-wine.git && \
    export MSVC_DOWNLOAD_ARGS=" \
        --accept-license \
        --channel release.ltsc.${MSVC_VERSION}  \
        --msvc-version ${MSVC_VERSION}  \
        --sdk-version ${WIN_SDK_VERSION} \
        Microsoft.Net.4.8.SDK \
        Microsoft.VisualStudio.MinShell \
    " && \
    CACHE_HASH=$(./msvc-wine/vsdownload.py --print-selection $MSVC_DOWNLOAD_ARGS | sha256sum | awk '{print $1}') && \
    MSVC_DIR="$RUNNER_TOOL_CACHE/msvc/$MSVC_VERSION-$CACHE_HASH" && \
    mkdir -p $MSVC_DIR /tmp/msvc-wine-cache && \
    ./msvc-wine/vsdownload.py $MSVC_DOWNLOAD_ARGS \
        --dest $MSVC_DIR \
        --cache /tmp/msvc-wine-cache && \
    wget -P /tmp/msvc-wine-cache https://github.com/kbandla/installers/releases/latest/download/X64.Debuggers.And.Tools-x64_en-us.msi && \
    msiextract -C $MSVC_DIR /tmp/msvc-wine-cache/X64.Debuggers.And.Tools-x64_en-us.msi && \
    ./msvc-wine/install.sh $MSVC_DIR && \
    mv /tmp/pdbcopy $MSVC_DIR/bin/x64/pdbcopy && \
    ln -sf ./pdbcopy $MSVC_DIR/bin/x64/pdbcopy.exe && \
    rm -rf /tmp/msvc-wine /tmp/msvc-wine-cache && \
    touch $MSVC_DIR.complete
