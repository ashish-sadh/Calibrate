#!/bin/bash
# Live cloud-interaction sweep: REAL Nebius round-trips for every DriftCore
# extraction path (coach ping, exercise text short/long, anti-hallucination,
# optional photo scan). Tier-4 — costs real API calls and 1-3 minutes; never
# runs on the commit path.
#
# Usage:
#   ./scripts/live-cloud-check.sh                         # text interactions
#   DRIFT_LIVE_SCAN_IMAGE=/path/to.jpg ./scripts/live-cloud-check.sh   # + photo scan
#
# Born from the workout-scan launch (builds 358-360): three shipped field bugs
# (token truncation, sampling nondeterminism, buffered-connection cellular
# kill) were ALL invisible to mocks and found only live. Run this after any
# change to RemoteLLMBackend, CloudExtractionPolicy, or an extraction prompt.
set -euo pipefail
cd "$(dirname "$0")/../DriftCore"
DRIFT_LIVE_CLOUD=1 swift test --filter LiveCloudInteractionTests 2>&1 \
  | grep -E "Test Case|passed|failed|Skip|error:" \
  | grep -v "^$"
