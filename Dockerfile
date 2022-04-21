FROM registry.tanzu.vmware.com/tanzu-application-platform/tap-packages@sha256:a8870aa60b45495d298df5b65c69b3d7972608da4367bd6e69d6e392ac969dd4

# All the direct Downloads need to run as root as they are going to /usr/local/bin
USER root

# TBS
RUN curl -L -o /usr/local/bin/kp https://github.com/vmware-tanzu/kpack-cli/releases/download/v0.4.2/kp-linux-0.4.2 && \
  chmod 755 /usr/local/bin/kp

# Knative
RUN curl -L -o /usr/local/bin/kn https://github.com/knative/client/releases/download/knative-v1.1.0/kn-linux-amd64 && \
    chmod 755 /usr/local/bin/kn

# Tanzu CLI
COPY tanzu-framework-linux-amd64.tar /tmp
RUN export TANZU_CLI_NO_INIT=true
RUN cd /tmp && tar -xvf "tanzu-framework-linux-amd64.tar" -C /tmp && \ 
    sudo install "cli/core/v0.11.2/tanzu-core-linux_amd64" /usr/local/bin/tanzu && \ 
    tanzu plugin install --local cli all
    
# Install tekton cli
RUN curl -LO https://github.com/tektoncd/cli/releases/download/v0.23.0/tkn_0.23.0_Linux_x86_64.tar.gz \
    && tar xvzf tkn_0.23.0_Linux_x86_64.tar.gz -C /usr/local/bin tkn \
    && chmod 755 /usr/local/bin/tkn

# Utilities
RUN apt-get update && apt-get install -y unzip openjdk-11-jdk

# Install krew
RUN \
( \
  set -x; cd "$(mktemp -d)" && \
  OS="$(uname | tr '[:upper:]' '[:lower:]')" && \
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" && \
  KREW="krew-${OS}_${ARCH}" && \
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" && \
  tar zxvf "${KREW}.tar.gz" && \
  ./"${KREW}" install krew \
)
RUN echo "export PATH=\"${KREW_ROOT:-$HOME/.krew}/bin:$PATH\"" >> ${HOME}/.bashrc
ENV PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
RUN kubectl krew install tree
RUN kubectl krew install view-secret
RUN kubectl krew install ctx
RUN kubectl krew install ns
RUN kubectl krew install konfig
RUN kubectl krew install eksporter
RUN kubectl krew install slice
RUN chmod 775 -R $HOME/.krew
RUN apt update
RUN apt install ruby-full -y

# Install Tanzu Dev Tools
COPY tanzu-vscode-extension.vsix /tmp
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version=4.3.0
RUN cp -rf /usr/lib/code-server/* /opt/code-server/
RUN rm -rf /usr/lib/code-server /usr/bin/code-server

RUN code-server --install-extension /tmp/tanzu-vscode-extension.vsix
RUN chown -R eduk8s:users /home/eduk8s/.cache
RUN chown -R eduk8s:users /home/eduk8s/.local

RUN curl -fsSL https://raw.githubusercontent.com/tilt-dev/tilt/master/scripts/install.sh | bash 
RUN chown -R eduk8s:users /home/eduk8s/.tilt-dev

# Cleanup directory

RUN rm -rf /tmp/*
RUN rm tkn_0.23.0_Linux_x86_64.tar.gz

USER 1001
COPY --chown=1001:0 . /home/eduk8s/
RUN fix-permissions /home/eduk8s
RUN rm /home/eduk8s/tanzu-framework-linux-amd64.tar
RUN rm /home/eduk8s/tanzu-vscode-extension.vsix
