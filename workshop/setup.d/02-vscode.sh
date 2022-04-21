#!/bin/bash
set -x
set +e

echo "\"java.server.launchMode\": \"Standard\"" >> /home/eduk8s/.local/share/code-server/User/settings.json
echo "\"tanzu.sourceImage\": \"${CONTAINER_REGISTRY_HOSTNAME}/tap-wkld/spring-sensors-source\"" >> /home/eduk8s/.local/share/code-server/User/settings.json
echo "\"tanzu.namespace\": \"${SESSION_NAMESPACE}\"" >> /home/eduk8s/.local/share/code-server/User/settings.json
echo "\"redhat.telemetry.enabled\": \"false\"" >> /home/eduk8s/.local/share/code-server/User/settings.json