#!/bin/bash

set -o errexit

__DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# shellcheck source=/dev/null
[[ -f "${__DIR}/pipeline.sh" ]] && source "${__DIR}/pipeline.sh" ||  \
 echo "No pipeline.sh found"

GCLOUD_PARENT_PATH="${GCLOUD_PARENT_PATH:-${HOME}/gcloud}"
		GCLOUD_PATH="${GCLOUD_PATH:-${GCLOUD_PARENT_PATH}/google-cloud-sdk}"
		if ! [ -x "${GCLOUD_PATH}" ]; then
			echo "installing gcloud.."
			downloadGCloud
		fi
#echo "moving to base folder"
#cd /
#echo "moving to root folder"
#cd /root
#echo "listing folder"
#ls		
source ~/.bashrc
#installing istio 
downloadIstio
cd istio-0.3.0
kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value core/account)
#kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=105226139860451521001
kubectl apply -f install/kubernetes/istio.yaml
#verify istio installation
kubectl get svc -n istio-system

#installing helm

downloadHelm "false"

helm init

kubectl create serviceaccount --namespace kube-system tiller
kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
kubectl patch deploy --namespace kube-system tiller-deploy -p '{"spec":{"template":{"spec":{"serviceAccount":"tiller"}}}}'
