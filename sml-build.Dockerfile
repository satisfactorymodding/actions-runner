ARG BASE_IMAGE="satisfactorymodding/actions-runner-base:latest"
FROM ${BASE_IMAGE}

RUN sudo apt-get update && sudo apt-get install -y --no-install-recommends zstd dos2unix && \
    sudo rm -rf /var/lib/apt/lists/*

# UnrealEngine
ARG UE_VERSION

RUN --mount=type=secret,id=GH_TOKEN \
    UE_DIR="$RUNNER_TOOL_CACHE/unrealengine/$UE_VERSION" && \
    mkdir -p $UE_DIR && \
    cd $UE_DIR && \
    GH_TOKEN="$(sudo cat /run/secrets/GH_TOKEN)" gh release download "${UE_VERSION}" --repo satisfactorymodding/UnrealEngine -p "UnrealEngine-CSS-Editor-Linux.tar.zst.*" && \
    cat UnrealEngine-CSS-Editor-Linux.tar.zst.* | zstd -d | tar -xf - && \
    rm UnrealEngine-CSS-Editor-Linux.tar.zst.* && \
    $UE_DIR/Engine/Binaries/Linux/UnrealVersionSelector -register && \
    touch $UE_DIR.complete

# Wwise caching
ARG WWISE_SDK_VERSION="2025.1.6.9117"

RUN --mount=type=secret,id=GH_TOKEN \
    --mount=type=secret,id=WWISE_EMAIL \
    --mount=type=secret,id=WWISE_PASSWORD \
    cd /tmp && \
    GH_TOKEN="$(sudo cat /run/secrets/GH_TOKEN)" gh release download --repo mircearoata/wwise-cli -p wwise-cli_linux_amd64 -O wwise-cli && \
    chmod +x ./wwise-cli && \
    WWISE_EMAIL="$(sudo cat /run/secrets/WWISE_EMAIL)" WWISE_PASSWORD="$(sudo cat /run/secrets/WWISE_PASSWORD)" \
    ./wwise-cli download --sdk-version "${WWISE_SDK_VERSION}" \
        --filter Packages=SDK \
        --filter DeploymentPlatforms=Windows_vc160 \
        --filter DeploymentPlatforms=Windows_vc170 \
        --filter DeploymentPlatforms=Linux \
        --filter DeploymentPlatforms= >/dev/null && \
    rm ./wwise-cli
