#!/bin/bash
set -x
set +e

REGISTRY_PASSWORD=$CONTAINER_REGISTRY_PASSWORD kp secret create registry-credentials --registry ${CONTAINER_REGISTRY_HOSTNAME} --registry-user ${CONTAINER_REGISTRY_USERNAME}

kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "registry-credentials"}, {"name": "tanzu-net-credentials"}]}'

jq ". + { \"java.server.launchMode\": \"Standard\", \"tanzu.sourceImage\": \"${CONTAINER_REGISTRY_HOSTNAME}/tap-wkld/spring-sensors-source\", \"tanzu.namespace\": \"${SESSION_NAMESPACE}\", \"redhat.telemetry.enabled\": false }" /home/eduk8s/.local/share/code-server/User/settings.json