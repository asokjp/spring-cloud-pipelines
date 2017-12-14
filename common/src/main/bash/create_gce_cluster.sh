#!/bin/bash

set -o errexit

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# shellcheck source=/dev/null
[[ -f "${__DIR}/pipeline.sh" ]] && source "${__DIR}/pipeline.sh" ||  \
 echo "No pipeline.sh found"


 
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && \
    chmod +x ./kubectl && \
    mv ./kubectl /usr/local/bin/kubectl
	

gcloud container clusters create test --zone us-central1-a --num-nodes 1 --machine-type n1-standard-4

gcloud container clusters get-credentials test --zone us-central1-a --project dulcet-hulling-185607

echo kubectl get nodes


