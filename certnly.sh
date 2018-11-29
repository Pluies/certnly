#!/bin/bash

set -euo pipefail

if [[ -z "$EMAIL" || -z "$DOMAINS" || -z "$SECRET_NAME" || -z "$EXISTING_SECRET_DIR" ]]
then
  echo "EMAIL, DOMAINS, SECRET_NAME, and EXISTING_SECRET_DIR env vars required"
  exit 1
fi

# Recreate the /etc/letsencrypt/ 
for f in $EXISTING_SECRET_DIR/*
do
  FROM=$f
  TO=$(echo $f | sed 's!__!/!g' | sed 's^'$EXISTING_SECRET_DIR'^^g')
  mkdir -p $(dirname $TO)
  cp $FROM $TO
done

# Serve /root over port 80 so that certbot can read its .well-known challenge
python -m SimpleHTTPServer 80 &

# Do the challenge!
certbot certonly --webroot -w "." -n --agree-tos --email "$EMAIL" --no-self-upgrade -d "$DOMAINS"

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
for f in $(find /etc/letsencrypt/ -type f -or -type l)
do
  echo "  \"$(echo $f | sed 's!/!__!g')\": \"$(cat $f | base64 -w0)\"," >> secret.json
done
echo "\"updated_at\": \"$(date|base64 -w0)\"}}" >> secret.json

# Update the secret in kubernetes
curl -v --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
     -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
     -k -v -XPATCH -H "Accept: application/json, */*" -H "Content-Type: application/strategic-merge-patch+json" \
     -d @secret.json https://${KUBERNETES_SERVICE_HOST}/api/v1/namespaces/${NAMESPACE}/secrets/${SECRET_NAME}
