#!/usr/bin/env bash
# Watch the leak -> OOMKilled -> restart cycle and the resulting alerts
set -euo pipefail
kubectl -n leaky-app get pods -w &
sleep 1
echo "Once a pod restarts, inspect:"
echo "  kubectl -n leaky-app get pods -o custom-columns=POD:.metadata.name,REASON:.status.containerStatuses[0].lastState.terminated.reason,RESTARTS:.status.containerStatuses[0].restartCount"
wait
