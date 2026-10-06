# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
FROM node:24-slim@sha256:0e0ff40c39bc087845bfb27465a0df4ea419520094bc35842ff83dd8cbe6f9b6 AS deps
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g pnpm@10.34.5
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY vendor ./vendor
# A credencial existe só neste RUN. Hooks/scripts não recebem o segredo.
RUN --mount=type=secret,id=npm_auth,target=/run/secrets/npmrc,required=true \
    NPM_CONFIG_USERCONFIG=/run/secrets/npmrc \
    pnpm install --frozen-lockfile --ignore-scripts --ignore-pnpmfile
RUN pnpm rebuild @prisma/client @prisma/engines prisma esbuild sharp @swc/core

FROM deps AS build
COPY . .
RUN AUTH_SECRET=build-placeholder \
    DATABASE_URL=postgresql://build:build@localhost:5432/build \
    pnpm build

FROM node:24-slim@sha256:0e0ff40c39bc087845bfb27465a0df4ea419520094bc35842ff83dd8cbe6f9b6 AS runner
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g prisma@6.19.3
ENV NODE_ENV=production HOSTNAME=0.0.0.0 PORT=5000
COPY --from=build /app/prisma ./prisma
COPY --from=build /app/.next/standalone ./
RUN useradd -u 10001 app && chown -R 10001:10001 /app \
    && mkdir -p /dados/anexos && chown -R 10001:10001 /dados
USER 10001
EXPOSE 5000
CMD ["node", "server.js"]
ARG DEPLOYED_REVISION
LABEL org.opencontainers.image.revision=$DEPLOYED_REVISION
