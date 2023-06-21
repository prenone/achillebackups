#!/bin/bash
docker build -t restic-safe-forget-server .
docker save restic-safe-forget-server > restic-safe-forget-server.tar