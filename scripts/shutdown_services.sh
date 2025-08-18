#!/bin/bash
# down.sh

docker compose -p lightrag-backend \
  -f infra.compose.yml \
  -f base.compose.yml \
  -f ./biz/strategy.compose.yml \
  -f ./biz/app.compose.yml \
  -f ./biz/gas.compose.yml up -d \
  --no-deps --force-recreate \
  lightrag-strategy lightrag-app lightrag-gas
