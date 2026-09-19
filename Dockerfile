FROM node:20.16.0-alpine AS build
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
ARG NPM_REGISTRY=https://registry.npmjs.org
ENV NPM_CONFIG_REGISTRY="${NPM_REGISTRY}"
RUN npm install -g pnpm@8.15.9 --registry="${NPM_REGISTRY}"
WORKDIR /usr/src/app
COPY . .
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
RUN pnpm --filter server exec jest --runInBand trpc.service.spec.ts
RUN pnpm --filter server build
RUN pnpm deploy --filter=server --prod /app && pnpm deploy --filter=server --prod /app-sqlite
RUN cd /app && pnpm exec prisma generate
RUN cd /app-sqlite && rm -rf prisma && mv prisma-sqlite prisma && pnpm exec prisma generate
# Keep only application runtime files, production dependencies and migrations.
RUN for dir in /app /app-sqlite; do \
      rm -rf "$dir/src" "$dir/test" "$dir/prisma-sqlite"; \
      find "$dir/dist" -type f \( -name '*.map' -o -name '*.ts' \) -delete; \
      find "$dir" -maxdepth 1 -type f ! -name package.json ! -name docker-bootstrap.sh -delete; \
      chmod +x "$dir/docker-bootstrap.sh"; \
    done

FROM node:20.16.0-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production HOST=0.0.0.0 DASHBOARD_ENABLED=false
ENV SERVER_ORIGIN_URL="" MAX_REQUEST_PER_MINUTE=60 AUTH_CODE=""
EXPOSE 4000
CMD ["./docker-bootstrap.sh"]

FROM runtime AS app-sqlite
ENV DATABASE_URL="file:../data/wewe-rss.db" DATABASE_TYPE=sqlite
COPY --from=build /app-sqlite /app

FROM runtime AS app
ENV DATABASE_URL="" DATABASE_TYPE=mysql
COPY --from=build /app /app
