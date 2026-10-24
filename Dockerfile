# syntax=docker/dockerfile:1

FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:24-alpine AS test
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm test

# Bake the imported Onvif/OASIS/W3C schemas into the image, so the container
# starts without internet access (see scripts/vendor-schemas.js).
FROM node:24-alpine AS schemas
WORKDIR /app
COPY scripts ./scripts
RUN node scripts/vendor-schemas.js /app/wsdl/vendor

FROM node:24-alpine AS runtime
WORKDIR /app

# The image runs `node main.js` with dependencies copied from the build stage; the
# npm/yarn toolchain that ships with the base image is dead weight at runtime and
# its bundled packages show up in vulnerability scans (see CHANGELOG 2.2.1).
RUN rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx \
           /usr/local/bin/corepack /usr/local/bin/yarn /usr/local/bin/yarnpkg /opt/yarn-v*

COPY --from=deps /app/node_modules ./node_modules
COPY package.json main.js ./
COPY src ./src
COPY wsdl ./wsdl
COPY --from=schemas /app/wsdl/vendor ./wsdl/vendor
COPY resources ./resources

ENV NODE_ENV=production

# WS-Discovery (udp/3702) plus each camera's own server/rtsp/snapshot ports,
# which are chosen in the config. Host or macvlan networking is expected.
EXPOSE 3702/udp

USER node

ENTRYPOINT ["node", "main.js"]
CMD ["/onvif.yaml"]
