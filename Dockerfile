# checkov:skip=CKV_DOCKER_2: This is not a running container. Its purpose is to be used in CI pipeline jobs
# checkov:skip=CKV_DOCKER_3: Kaniko must be root to work
# checkov:skip=CKV_DOCKER_8: Kaniko must be root to work
ARG BASE_REGISTRY
FROM ${BASE_REGISTRY}alpine:3.17 AS builder

ARG VAULT_VERSION=1.13.1
ARG ENVCONSUL_VERSION=0.13.1

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN --mount=type=cache,target=/var/cache/apk \
    apk update --update \
    && apk add curl npm tar unzip bash --no-cache --update \
    && curl -sSLO "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64" \
    && chmod +x ./argocd-linux-amd64 \
    && mv ./argocd-linux-amd64 /usr/local/bin/argocd \
    && curl -sSLO "https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64" \
    && chmod +x ./kubectl-argo-rollouts-linux-amd64 \
    && mv ./kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts \
    && curl -sSL "https://mirror.openshift.com/pub/openshift-v4/clients/oc/latest/linux/oc.tar.gz" -o /tmp/oc.tar.gz \
    && tar -xzf /tmp/oc.tar.gz -C /usr/local/bin \
    && rm /tmp/oc.tar.gz \
    && KUBECTL_VERSION=$(curl -L "https://storage.googleapis.com/kubernetes-release/release/stable.txt") \
    && curl -sSLO "https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && chmod +x ./kubectl \
    && mv ./kubectl /usr/local/bin/kubectl \
    && curl -sSfLO "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip" \
    && unzip -o "./vault_${VAULT_VERSION}_linux_amd64.zip" -d /usr/local/bin \
    && curl -sSfLO "https://releases.hashicorp.com/envconsul/${ENVCONSUL_VERSION}/envconsul_${ENVCONSUL_VERSION}_linux_amd64.zip" \
    && unzip -o "./envconsul_${ENVCONSUL_VERSION}_linux_amd64.zip" -d /usr/local/bin \
    && curl -sSfL "https://install-cli.jfrog.io" | sh \
    && curl -sSfL "https://raw.githubusercontent.com/anchore/grype/main/install.sh" | sh -s -- -b /usr/local/bin \
    && curl -sSfL "https://raw.githubusercontent.com/anchore/syft/main/install.sh" | sh -s -- -b /usr/local/bin \
    && curl -sSL -o /usr/local/bin/semver "https://raw.githubusercontent.com/fsaintjacques/semver-tool/master/src/semver" \
    && chmod +x /usr/local/bin/semver \
    && npm install -g github-files-fetcher \
    && fetcher --url="https://github.com/aquasecurity/trivy/tree/main/contrib" --out=/mnt \
    && KYVERNO_VERSION=$(curl -kL "https://github.com/kyverno/kyverno/releases/latest" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sort | uniq | tail -1) \
    && curl -sSfLO "https://github.com/kyverno/kyverno/releases/download/${KYVERNO_VERSION}/kyverno-cli_${KYVERNO_VERSION}_linux_x86_64.tar.gz" \
    && tar -xzf kyverno-cli_${KYVERNO_VERSION}_linux_x86_64.tar.gz \
    && mv kyverno /usr/local/bin/kyverno \
    && curl -L -o vcluster "https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-linux-amd64" \
    && install -c -m 0755 vcluster /usr/local/bin && rm -f vcluster \
    && curl -s https://fluxcd.io/install.sh | bash

FROM ${BASE_REGISTRY}moby/buildkit:master as buildkit

FROM ${BASE_REGISTRY}ixxel/musl-dns-hack-alpine as dnshack

FROM ${BASE_REGISTRY}python:3.11-alpine3.17 as binaries

COPY --from=dnshack /lib/ld-musl-x86_64.so.1 /lib/ld-musl-x86_64.so.1

COPY --from=buildkit /usr/bin/ /usr/bin/

COPY --from=gcr.io/kaniko-project/executor:latest /kaniko/executor /usr/local/bin/executor

COPY --from=builder /usr/local/bin/oc \
                    /usr/local/bin/kubectl-argo-rollouts \
                    /usr/local/bin/grype \
                    /usr/local/bin/syft \
                    /usr/local/bin/jf \
                    /usr/local/bin/semver \
                    /usr/local/bin/envconsul \
                    /usr/local/bin/vault \
                    /usr/local/bin/argocd \
                    /usr/local/bin/kubectl \
                    /usr/local/bin/kyverno \
                    /usr/local/bin/vcluster \
                    /usr/local/bin/flux \
                    /usr/local/bin/

FROM binaries as certs

ENV TZ="Europe/Paris"

COPY ./pki_root_ca.pem /usr/local/share/ca-certificates/root.crt
COPY ./pki_int_ca.pem /usr/local/share/ca-certificates/int.crt

RUN --mount=type=cache,target=/var/cache/apk \
    apk add --update \
    tzdata \
    ca-certificates \
    && cp /usr/share/zoneinfo/${TZ} /etc/localtime \
    && update-ca-certificates

FROM certs as finalbase

# COPY --from=builder /mnt/contrib /root/contrib

RUN --mount=type=cache,target=/var/cache/apk \
    apk update \
    && apk upgrade \
    && apk add  --update \
    fuse3 fuse-overlayfs openssh pigz shadow-uidmap xz \
    libc6-compat \
    img \ 
    git \
    curl \
    img \
    podman \
    podman-docker \
    buildah \
    skopeo \
    gettext \
    bash \
    jq \
    yq \
    bind-tools \
    util-linux \
    tzdata \
    openssl \
    moreutils

    # && helm plugin install "https://github.com/datreeio/helm-datree" \
    # && rm -f /var/lib/containers/storage/libpod/bolt_state.db \
    # && sed -i "s/driver = \"overlay\"/driver = \"vfs\"/" /etc/containers/storage.conf \
    # && curl -sL https://raw.githubusercontent.com/slimtoolkit/slim/master/scripts/install-slim.sh | bash -

FROM finalbase

LABEL maintainer="Frederic Spiers <fredspiers@gmail.com>" \
      component="CI/CD tools"

ARG BUILD_VERSION
    
ENV PATH="/kaniko:$PATH" \
    IMG_VERSION="$BUILD_VERSION"

RUN --mount=type=cache,target=/var/cache/apk \
    apk add  --update --repository="http://dl-cdn.alpinelinux.org/alpine/edge/community" \
    github-cli \
    terraform \
    kustomize \
    helm \
    cosign

RUN --mount=type=cache,target=/var/cache/apk \
    apk add  --update --repository="http://dl-cdn.alpinelinux.org/alpine/edge/testing" \
    trivy

RUN helm plugin install "https://github.com/chartmuseum/helm-push" \
    && helm plugin install "https://github.com/databus23/helm-diff" \
    && helm plugin install "https://github.com/helm-unittest/helm-unittest.git" \
    && helm plugin install "https://github.com/datreeio/helm-datree" \
    && pip3 install --no-cache-dir --upgrade python-gitlab ansible \
    && sed -i 's/^#mount_program/mount_program/' /etc/containers/storage.conf

ENV HELM_PLUGINS="/root/.local/share/helm/plugins"

ENV TEST=gh

RUN mkdir -p /home/test