FROM debian

RUN apt -y update && apt -y upgrade && apt -y install curl lsof procps findutils ripgrep wget build-essential cmake rustup tini git jq sox python3 python-is-python3 python3-yaml libssl-dev pkg-config tmux qdbus-qt6 libnotify-bin nodejs \
libnspr4 libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64 \
  libcups2t64 libgbm1 libxkbcommon0 libcairo2 libpango-1.0-0 \
  libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libxi6 \
  fonts-dejavu-core fonts-liberation golang bc sqlite3 git-filter-repo bubblewrap
RUN mkdir -p -m 755 /etc/apt/keyrings \
	&& out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
	&& cat $out > /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& mkdir -p -m 755 /etc/apt/sources.list.d \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
	&& apt update \
	&& apt install gh -y \
	&& wget https://github.com/fastly/cli/releases/download/v14.2.0/fastly_14.2.0_linux_amd64.deb \
	&& apt install ./fastly_14.2.0_linux_amd64.deb \
	&& rm fastly_14.2.0_linux_amd64.deb
# Voice mode captures through ALSA (arecord, or sox `rec` as fallback), but the
# host runs PipeWire and owns the real devices, so cclaude hands over the
# pipewire-pulse socket instead. Point ALSA's default device at it.
RUN apt -y update && apt -y install alsa-utils libasound2-plugins libsox-fmt-pulse pulseaudio-utils \
	&& printf 'pcm.!default { type pulse }\nctl.!default { type pulse }\n' > /etc/asound.conf
# Container workloads run on rootless Podman. podman-docker supplies the docker
# CLI and pulls in Compose v2. crun gives each container a session keyring,
# which the wrapper's seccomp profile denies, so turn that off.
RUN apt -y update && apt -y install podman podman-docker uidmap passt \
	&& touch /etc/containers/nodocker \
	&& mkdir -p /etc/containers/containers.conf.d \
	&& printf '[containers]\nkeyring = false\n\n[engine]\ncompose_providers = ["/usr/local/bin/docker-compose"]\ncompose_warning_logs = false\n' > /etc/containers/containers.conf.d/99-cclaude.conf
COPY compose-launcher /usr/local/bin/docker-compose
# The wrapper hands the container CAP_SYS_ADMIN so that newuidmap can write a
# multi-range uid_map. Every other setuid binary would gain the same reach, and
# none of them are needed here, so leave the id-mapping helpers as the only two.
RUN find / -xdev -perm -4000 -type f ! -name newuidmap ! -name newgidmap -exec chmod u-s {} +
COPY entrypoint /usr/local/bin/
ENTRYPOINT ["/bin/tini", "--", "/usr/local/bin/entrypoint"]
CMD ["--allow-dangerously-skip-permissions"]
