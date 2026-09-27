#!/usr/bin/env bash
# Build every app in apps/ and push it to its ECR repo.
# Usage: ./scripts/push-images.sh [tag]      (default tag: v1)
set -euo pipefail

TAG="${1:-v1}"
REGION="${AWS_REGION:-us-west-2}"
PREFIX="${PREFIX:-notes-dev}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "Logging in to ${REGISTRY}"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

cd "$(dirname "$0")/../apps"
for dir in */; do
  app="${dir%/}"
  image="${REGISTRY}/${PREFIX}/${app}:${TAG}"
  echo "==> ${app} -> ${image}"
  # Fargate tasks run on ARM64 (Graviton) in this project, which matches Apple Silicon Macs
  docker build --platform linux/arm64 -t "$image" "$app"
  docker push "$image"
done
echo "Done. Pushed tag ${TAG}."
