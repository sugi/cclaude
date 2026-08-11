FROM debian

RUN apt -y update && apt -y upgrade && apt -y install curl lsof procps findutils ripgrep wget build-essential cmake rustup tini git sudo jq sox python3 python-is-python3 python3-yaml libssl-dev pkg-config tmux qdbus-qt6 libnotify-bin \
libnspr4 libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64 \
  libcups2t64 libgbm1 libxkbcommon0 libcairo2 libpango-1.0-0 \
  libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libxi6 \
  fonts-dejavu-core fonts-liberation golang bc sqlite3
RUN sudo mkdir -p -m 755 /etc/apt/keyrings \
	&& out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
	&& cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& sudo mkdir -p -m 755 /etc/apt/sources.list.d \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	&& sudo apt update \
	&& sudo apt install gh -y \
	&& wget https://github.com/fastly/cli/releases/download/v14.2.0/fastly_14.2.0_linux_amd64.deb \
	&& apt install ./fastly_14.2.0_linux_amd64.deb \
	&& rm fastly_14.2.0_linux_amd64.deb
COPY entrypoint /usr/local/bin/
ENTRYPOINT ["/bin/tini", "--", "/usr/local/bin/entrypoint"]
CMD ["--allow-dangerously-skip-permissions"]
