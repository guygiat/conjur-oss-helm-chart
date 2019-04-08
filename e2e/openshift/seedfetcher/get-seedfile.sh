#!/bin/bash
set -euo pipefail

if [[ "${MASTER_HOSTNAME}" == "" ]]; then
    echo "ERROR: MASTER_HOSTNAME not set!"
    exit 1
fi

if [[ "${AUTHENTICATOR_ID}" == "" ]]; then
    echo "ERROR: AUTHENTICATOR_ID not set!"
    exit 1
fi

MASTER_SSL_CERT_PATH="/tmp/master.crt"
TOKEN_PATH="/run/secrets/kubernetes.io/serviceaccount/token"

echo "Trying to fetch seedfile from $MASTER_HOSTNAME..."
echo "Hostname: $FOLLOWER_HOSTNAME"

echo "$CONJUR_SSL_CERTIFICATE" > "$MASTER_SSL_CERT_PATH"
echo "Using master ssl cert from ${MASTER_SSL_CERT_PATH}"

export CONJUR_APPLIANCE_URL="https://$MASTER_HOSTNAME"
export CONJUR_AUTHN_URL="$CONJUR_APPLIANCE_URL/authn-k8s/$AUTHENTICATOR_ID"

WGET_CERT_ARGS=( "--ca-certificate" "${MASTER_SSL_CERT_PATH}" )
if [ "${MASTER_SSL_CERT_PATH}" == "" ]; then
  echo "WARNING: No master SSL cert set!"
  echo "WARNING: This connection is succeptioble to MITM attacks!"
  WGET_CERT_ARGS=( "--no-check-certificate" )
fi

echo "Extracting service account..."
SERVICE_ACCOUNT_NAME=$(cat "$TOKEN_PATH" | awk -F. {'print $2'} | base64 -d | jq -r '."kubernetes.io/serviceaccount/service-account.name"')

export CONJUR_AUTHN_LOGIN="host/conjur/authn-k8s/$AUTHENTICATOR_ID/apps/$MY_POD_NAMESPACE/service_account/$SERVICE_ACCOUNT_NAME"

echo "Configuration:"
echo "- CONJUR_ACCOUNT: $CONJUR_ACCOUNT"
echo "- CONJUR_APPLIANCE_URL: $CONJUR_APPLIANCE_URL"
echo "- CONJUR_AUTHN_URL: $CONJUR_AUTHN_URL"
echo "- CONJUR_AUTHN_LOGIN: $CONJUR_AUTHN_LOGIN"
echo "- SERVICE_ACCOUNT_NAME: $SERVICE_ACCOUNT_NAME"
echo "- WGET_CERT_ARGS: ${WGET_CERT_ARGS[@]}"
echo

echo "Running authenticator..."
/usr/bin/authenticator

echo "Parsing Conjur token..."
conjur_api_token=$(cat "/run/conjur/access-token" | base64 | tr -d '\n')

if [[ "${conjur_api_token}" == "" ]]; then
  echo "ERROR: API token is invalid (empty)!"
  exit 1
fi

conjur_seed_file_url="$CONJUR_APPLIANCE_URL/configuration/$CONJUR_ACCOUNT/seed/follower"
echo "Fetching seed file from $conjur_seed_file_url"

follower_altname="$FOLLOWER_HOSTNAME.$MY_POD_NAMESPACE.svc.cluster.local"
follower_hostnames="$FOLLOWER_HOSTNAME,$follower_altname"
echo "Using hostnames: '$follower_hostnames'"

wget --post-data "follower_hostname=$follower_hostnames" \
     --header "Authorization: Token token=\"$conjur_api_token\"" \
     "${WGET_CERT_ARGS[@]}" \
     -O "$SEEDFILE_DIR/follower-seed.tar" \
     "$conjur_seed_file_url"

echo "Seedfile downloaded!"