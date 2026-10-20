FROM docker.io/library/node:24.21.0-bookworm-slim AS common

USER root
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    ca-certificates chromium coreutils curl git make g++ python3 \
    && rm -rf /var/lib/apt/lists/*
RUN set -eu; \
    case "$(dpkg --print-architecture)" in \
      arm64) architecture=aarch64 ;; amd64) architecture=x86_64 ;; \
      *) echo "Unsupported Gleam architecture" >&2; exit 1 ;; \
    esac; \
    asset="gleam-v1.18.1-${architecture}-unknown-linux-musl.tar.gz"; \
    cd /tmp; \
    curl -fsSLO --retry 3 --retry-all-errors --connect-timeout 10 --max-time 120 \
      "https://github.com/gleam-lang/gleam/releases/download/v1.18.1/${asset}"; \
    curl -fsSLO --retry 3 --retry-all-errors --connect-timeout 10 --max-time 120 \
      "https://github.com/gleam-lang/gleam/releases/download/v1.18.1/${asset}.sha256"; \
    sha256sum --check "${asset}.sha256"; \
    tar -xzf "${asset}" -C /usr/local/bin gleam; \
    rm "${asset}" "${asset}.sha256"
ARG NPM_REGISTRY=https://registry.npmjs.org/
ENV npm_config_registry="${NPM_REGISTRY}"
RUN npm install --global --quiet --allow-scripts=pnpm pnpm@12.13.0

WORKDIR /opt/shared-tree
COPY benchmark/ ./
RUN pnpm install --registry="${NPM_REGISTRY}" --frozen-lockfile
ENV PATH="/opt/shared-tree/node_modules/.bin:${PATH}" \
    WATERSHED_CHROME="/usr/local/bin/shared-tree-chromium" \
    SHARED_TREE_APP_PORT="4173" \
    SHARED_TREE_SERVICE_STATE_ROOT="/tmp"
RUN printf '#!/bin/sh\nexec /usr/bin/chromium --no-sandbox --disable-dev-shm-usage "$@"\n' \
    > /usr/local/bin/shared-tree-chromium \
    && chmod 755 /usr/local/bin/shared-tree-chromium

COPY baseline/ /opt/shared-tree/baseline/
WORKDIR /opt/shared-tree/baseline
RUN pnpm install --registry="${NPM_REGISTRY}" --frozen-lockfile && pnpm check && pnpm build
RUN chmod -R a+rX /opt/shared-tree/baseline
WORKDIR /opt/shared-tree

FROM common AS task
USER 1000:1000
CMD ["sh"]

FROM common AS grade
USER root
COPY grading/ /opt/shared-tree/grading/
RUN cp -a /opt/shared-tree/baseline/node_modules /opt/shared-tree/grading/workspace/ \
    && if [ -d /opt/shared-tree/baseline/build ]; then \
      cp -a /opt/shared-tree/baseline/build /opt/shared-tree/grading/workspace/; \
    fi
USER 1000:1000
CMD ["sh"]
