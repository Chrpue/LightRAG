#!/bin/bash
# down.sh

docker compose -p lightrag-backend down -v --remove-orphans
