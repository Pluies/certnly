#!/bin/bash

set -euo pipefail

if [[ -z "$EMAIL" || -z "$DOMAINS" || -z "$SECRET_NAME" || -z "$EXISTING_SECRET_TAR" ]]
then
  echo "EMAIL, DOMAINS, SECRET_NAME, and EXISTING_SECRET_DIR env vars required"
  exit 1
fi

# Recreate the /etc/letsencrypt/ folder and subdirectories
pushd /
tar -xzvf $EXISTING_SECRET_TAR
popd

# Serve /root over port 80 so that certbot can read its .well-known challenge
python -m SimpleHTTPServer 80 &

# Do the challenge!
certbot certonly --webroot -w "." -n --agree-tos --email "$EMAIL" --no-self-upgrade -d "$DOMAINS"

# Recompress /etc/letsencrypt
NEW_TAR=/tmp/letsencrypt.tar.gz
pushd /
tar -czvf $NEW_TAR /etc/letsencrypt/
popd

# Generate the updated secret
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

# Update the secret in kubernetes
curl -v --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
     -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
     -k -v -XPUT -H "Accept: application/json, */*" -H "Content-Type: application/json" \
     -d @secret.json https://${KUBERNETES_SERVICE_HOST}/api/v1/namespaces/${NAMESPACE}/secrets/${SECRET_NAME}
