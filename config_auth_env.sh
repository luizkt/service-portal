#/bin/bash

echo "PG_PASS=$(openssl rand -base64 36 | tr -d '\n')" >> .env
echo "AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')" >> .env
echo "ORCHESTRATOR_JWT_SECRET=$(openssl rand -base64 60 | tr -d '\n')" >> .env