#!/usr/bin/env bash

# Common utilities for Don RDNA Lab

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[$(date +%H:%M:%S)] $1${NC}"; }
warn()  { echo -e "${YELLOW}[$(date +%H:%M:%S)] WARNING: $1${NC}"; }
error() { echo -e "${RED}[$(date +%H:%M:%S)] ERROR: $1${NC}" >&2; }

require_cmd() {
    command -v "$1" &>/dev/null || { error "$1 not found"; return 1; }
}
