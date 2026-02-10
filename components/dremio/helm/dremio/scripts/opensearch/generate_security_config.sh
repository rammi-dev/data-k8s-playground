#
# Copyright (C) 2017-2019 Dremio Corporation. This file is confidential and private property.
#

#/bin/bash
set -e

SECRET_NAME=$1
CONFIG_TEMPLATE_PATH=$2
ENABLE_HTTP_BASIC_AUTH=$3
NAMESPACE=$4
COORDINATOR_SERVICE_ACCOUNT=$5
ROLES_MAPPING_TEMPLATE_PATH=$6
CLUSTER_DOMAIN=$7

# Use proxy to add auth header, the proxy parses issuer from service account
# token and uses to get public signing keys.
JWKS_URI="http://oidc-proxy.$NAMESPACE.svc.$CLUSTER_DOMAIN"
# Read config and replace PEM in it.
CONFIG=$(cat "$CONFIG_TEMPLATE_PATH")
CONFIG="${CONFIG//<ENABLE_HTTP_BASIC_AUTH>/$ENABLE_HTTP_BASIC_AUTH}"
CONFIG="${CONFIG//<JWKS_URI>/$JWKS_URI}"

echo "CONFIG: $CONFIG"

# Read roles_mapping.yml and replace service account name in it.
ROLES_MAPPING=$(cat $ROLES_MAPPING_TEMPLATE_PATH)
ROLES_MAPPING="${ROLES_MAPPING//<NAMESPACE>/$NAMESPACE}"
ROLES_MAPPING="${ROLES_MAPPING//<COORDINATOR_SERVICE_ACCOUNT>/$COORDINATOR_SERVICE_ACCOUNT}"

# Create the Kubernetes secret, make sure it does not exist before creating it.
kubectl delete secret $SECRET_NAME --ignore-not-found
kubectl create secret generic $SECRET_NAME \
--from-literal=config.yml="$CONFIG" \
--from-literal=roles_mapping.yml="$ROLES_MAPPING" \
--dry-run=client -o yaml | kubectl apply -f -
