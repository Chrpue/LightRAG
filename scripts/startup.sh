#!/bin/bash
# up.sh

docker compose --profile run -p lightrag-backend \
  -f infra.compose.yml \
  -f base.compose.yml \
  -f ./biz/strategy.compose.yml \
  -f ./biz/app.compose.yml \
  -f ./biz/gas.compose.yml \
  up -d --build --force-recreate
