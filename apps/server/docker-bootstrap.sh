#!/bin/sh
set -eu
# Use bundled Prisma only; never download dependencies at container startup.
./node_modules/.bin/prisma migrate deploy
exec node dist/main
