#!/bin/bash

set -eo pipefail

log () {
  echo "[$(date)] $1"
}

if [[ -z "$EMAIL" || -z "$DOMAINS" || -z "$SECRET_NAME" || -z "$EXISTING_SECRET_TAR" ]]
then
  log "EMAIL, DOMAINS, SECRET_NAME, and EXISTING_SECRET_TAR env vars required"
  exit 1
fi

# Deal with STAGING_FLAG, then start catching unset vars
if [[ "$USE_STAGING" == "true" ]]
then
  STAGING_FLAG="--staging"
  log "Using staging letsencrypt - certificates will be invalid"
else
  STAGING_FLAG=""
  log "Using production letsencrypt"
fi

set -u

log "Recreating the /etc/letsencrypt/ folder and subdirectories"
(cd / && tar -xzf $EXISTING_SECRET_TAR)

log "Serving /root over port 80 so that certbot can read its .well-known challenge"
python -m SimpleHTTPServer 80 &
sleep 5 # Give python some time to set up before letsencrypt

log "Processing letsencrypt challenge!"
CERTBOT_CMD="certbot certonly $STAGING_FLAG --webroot -w '.' -n --agree-tos --email '$EMAIL' --no-self-upgrade --cert-name '$SECRET_NAME' -d '$DOMAINS'"

log "Using command: $CERTBOT_CMD"
eval $CERTBOT_CMD

log "Recompressing /etc/letsencrypt"
NEW_TAR=/tmp/letsencrypt.tar.gz
(cd / && tar -czf $NEW_TAR /etc/letsencrypt/)

log "Generating the updated secret"
cat <<SECRET > secret.json
{
  "kind": "Secret",
  "apiVersion": "v1",
  "metadata": {
     "name": "${SECRET_NAME}",
     "namespace": "${NAMESPACE}"
  },
  "type": "Opaque",
  "data": {
SECRET
echo -n '"letsencrypt.tar.gz": "' >> secret.json
base64 -w0 < $NEW_TAR             >> secret.json
echo -n '"}}'                     >> secret.json

log "Updating the secret in kubernetes..."
curl --silent --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
     -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
     -XPUT -H "Accept: application/json, */*" -H "Content-Type: application/json" \
     -d @secret.json https://${KUBERNETES_SERVICE_HOST}/api/v1/namespaces/${NAMESPACE}/secrets/${SECRET_NAME} \
     -o /dev/null -w "Status: %{http_code}\n"

log "Secret updated, all done!"
