FROM node:20.20.2-alpine AS base

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
WORKDIR /app

FROM base AS deps

RUN apk add --no-cache libc6-compat \
  && corepack enable \
  && corepack prepare pnpm@9.15.4 --activate

COPY package.json pnpm-lock.yaml ./

RUN --mount=type=cache,id=objectstorage-frontend-pnpm,target=/pnpm/store \
  pnpm install --frozen-lockfile

FROM base AS builder

RUN corepack enable \
  && corepack prepare pnpm@9.15.4 --activate

ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_OPTIONS=--max-old-space-size=8192

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# The production config is mounted by the Helm chart at runtime. A valid
# build-time config keeps Next.js instrumentation checks active in Docker builds.
RUN mkdir -p /app/data \
  && cp ./data/config.example.yaml /app/data/config.yaml

RUN --mount=type=cache,id=objectstorage-frontend-next,target=/app/.next/cache \
  pnpm build

FROM base AS runner

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

RUN addgroup --system --gid 1001 nodejs \
  && adduser --system --uid 1001 nextjs \
  && apk add --no-cache ca-certificates curl dumb-init \
  && update-ca-certificates \
  && mkdir -p /app/data \
  && chown -R nextjs:nodejs /app

COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

USER nextjs

EXPOSE 3000

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "server.js"]
