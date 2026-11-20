ARG BASE_IMAGE="satisfactorymodding/actions-runner-base:latest"
FROM ${BASE_IMAGE}

RUN sudo apt-get update && sudo apt-get install -y --no-install-recommends 7zip zstd && \
    sudo rm -rf /var/lib/apt/lists/*

# UE gitdeps
ARG UE_COMMITISH="5.6.1-CSS"

ENV UE_GITDEPS=/opt/ue-gitdeps
RUN --mount=type=secret,id=GH_TOKEN \
    mkdir -p /tmp/ue && cd /tmp/ue && \
    sudo mkdir -p $UE_GITDEPS && sudo chown runner:docker $UE_GITDEPS && \
    git clone --depth 1 --single-branch --branch "$UE_COMMITISH" --filter=blob:none --sparse "https://$(sudo cat /run/secrets/GH_TOKEN)@github.com/satisfactorymodding/UnrealEngine.git" . && \
    git sparse-checkout init --cone && \
    git sparse-checkout set Engine/Binaries/DotNET/GitDependencies Engine/Build && \
    ./Engine/Binaries/DotNET/GitDependencies/linux-x64/GitDependencies && \
    cd / && rm -rf /tmp/ue

# InnoSetup
ARG INNOSETUP_VERSION="6.7.2"

RUN wget -O /tmp/innosetup.exe https://github.com/jrsoftware/issrc/releases/download/is-$(echo $INNOSETUP_VERSION | tr '.' '_')/innosetup-${INNOSETUP_VERSION}.exe && \
    xvfb-run -a wine reg add "HKEY_CURRENT_USER\Software\Wine" /v ShowDotFiles /d Y && \
    xvfb-run -a wine /tmp/innosetup.exe /SP- /VERYSILENT /ALLUSERS /SUPPRESSMSGBOXES && \
    rm -f /tmp/innosetup.exe && \
    wineserver -w
