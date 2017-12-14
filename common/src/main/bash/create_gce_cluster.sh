#!/bin/bash

set -o errexit

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# shellcheck source=/dev/null
[[ -f "${__DIR}/pipeline.sh" ]] && source "${__DIR}/pipeline.sh" ||  \
 echo "No pipeline.sh found"


 
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && \
    chmod +x ./kubectl && \
    mv ./kubectl /usr/local/bin/kubectl
	
GCLOUD_PARENT_PATH="${GCLOUD_PARENT_PATH:-${HOME}/gcloud}"
		GCLOUD_PATH="${GCLOUD_PATH:-${GCLOUD_PARENT_PATH}/google-cloud-sdk}"
		if ! [ -x "${GCLOUD_PATH}" ]; then
			echo "installing gcloud.."
			downloadGCloud
			gcloud init
		fi

		cd /
gcloud container clusters create test --zone us-central1-a --num-nodes 1 --machine-type n1-standard-4

gcloud container clusters get-credentials test --zone us-central1-a --project dulcet-hulling-185607

echo kubectl get nodes


function downloadGCloud() {
 if [[ "${OSTYPE}" == linux* ]]; then
			OS_TYPE="linux"
		else
			OS_TYPE="darwin"
		fi
		GCLOUD_VERSION="${GCLOUD_VERSION:-172.0.1}"
		GCLOUD_ARCHIVE="${GCLOUD_ARCHIVE:-google-cloud-sdk-${GCLOUD_VERSION}-${OS_TYPE}-x86_64.tar.gz}"
		GCLOUD_PARENT_PATH="${GCLOUD_PARENT_PATH:-${HOME}/gcloud}"
		GCLOUD_PATH="${GCLOUD_PATH:-${GCLOUD_PARENT_PATH}/google-cloud-sdk}"
		wget -P "${GCLOUD_PARENT_PATH}/" \
                "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/${GCLOUD_ARCHIVE}"
		pushd "${GCLOUD_PARENT_PATH}/" || exit
		tar xvf "${GCLOUD_ARCHIVE}"
		rm -vf -- "${GCLOUD_ARCHIVE}"
		echo "Running the installer"
		"${GCLOUD_PATH}/install.sh"
		popd || exit

}


