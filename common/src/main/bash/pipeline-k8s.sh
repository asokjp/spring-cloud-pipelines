#!/bin/bash

set -e

function logInToPaas() {
	local ca="PAAS_${ENVIRONMENT}_CA"
	local k8sCa="${!ca}"
	local clientCert="PAAS_${ENVIRONMENT}_CLIENT_CERT"
	local k8sClientCert="${!clientCert}"
	local clientKey="PAAS_${ENVIRONMENT}_CLIENT_KEY"
	local k8sClientKey="${!clientKey}"
	local tokenPath="PAAS_${ENVIRONMENT}_CLIENT_TOKEN_PATH"
	local k8sTokenPath="${!tokenPath}"
	local clusterName="PAAS_${ENVIRONMENT}_CLUSTER_NAME"
	local k8sClusterName="${!clusterName}"
	local clusterUser="PAAS_${ENVIRONMENT}_CLUSTER_USERNAME"
	local k8sClusterUser="${!clusterUser}"
	local systemName="PAAS_${ENVIRONMENT}_SYSTEM_NAME"
	local k8sSystemName="${!systemName}"
	local api="PAAS_${ENVIRONMENT}_API_URL"
	local apiUrl="${!api:-192.168.99.100:8443}"
	echo "Downloading CLI"
	curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/darwin/amd64/kubectl" --fail
	chmod +x "${KUBECTL_BIN}"
	echo "Removing current Kubernetes configuration"
	#rm -rf "${KUBE_CONFIG_PATH}" || echo "Failed to remove Kube config. Continuing with the script"
	GCLOUD_PARENT_PATH="${GCLOUD_PARENT_PATH:-${HOME}/gcloud}"
		GCLOUD_PATH="${GCLOUD_PATH:-${GCLOUD_PARENT_PATH}/google-cloud-sdk}"
		if ! [ -x "${GCLOUD_PATH}" ]; then
			echo "installing gcloud.."
			downloadGCloud
		fi
	echo "Logging in to Kubernetes API [${apiUrl}], with cluster name [${k8sClusterName}] and user [${k8sClusterUser}]"
	#"${KUBECTL_BIN}" config set-cluster "${k8sClusterName}" --server="https://${apiUrl}" --certificate-authority="${k8sCa}" --embed-certs=true
	# TOKEN will get injected as a credential if present
	#if [[ "${TOKEN}" != "" ]]; then
	#	"${KUBECTL_BIN}" config set-credentials "${k8sClusterUser}" --token="${TOKEN}"
	#elif [[ "${k8sTokenPath}" != "" ]]; then
	#	local tokenContent
	#	tokenContent="$(cat "${k8sTokenPath}")"
	#	"${KUBECTL_BIN}" config set-credentials "${k8sClusterUser}" --token="${tokenContent}" --kubeconfig="${KUBE_CONFIG_PATH}"
	#else
	#	"${KUBECTL_BIN}" config set-credentials "${k8sClusterUser}" --certificate-authority="${k8sCa}" --client-key="${k8sClientKey}" --client-certificate="${k8sClientCert}"  --kubeconfig="${KUBE_CONFIG_PATH}"
	#fi
	#"${KUBECTL_BIN}" config set-context "${k8sSystemName}" --cluster="${k8sClusterName}" --user="${k8sClusterUser}"  --kubeconfig="${KUBE_CONFIG_PATH}"
	#"${KUBECTL_BIN}" config use-context "${k8sSystemName}" --kubeconfig="${KUBE_CONFIG_PATH}"
	#./google-cloud-sdk/bin/gcloud init
	#gcloud container clusters get-credentials test --zone us-central1-c --project third-apex-181907
	echo "CLI version"
	"${KUBECTL_BIN}" version
}

function downloadHelm() {
#HELM_VERSION="${HELM_VERSION:-v2.7.0-linux-amd64}"
#HELM_ARCHIVE="${HELM_ARCHIVE:-helm-${HELM_VERSION}-${OS_TYPE}.tar.gz}"
#wget "https://kubernetes-helm.storage.googleapis.com/${HELM_ARCHIVE}"
#tar xvf "${HELM_ARCHIVE}"
#rm -vf -- "${HELM_ARCHIVE}"
#mv linux-amd64/helm /usr/local/bin/helm
	if ! [ -x "/usr/local/bin/helm" ]; then
		echo "installing helm.."
		curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get > get_helm.sh
		chmod 700 get_helm.sh
		./get_helm.sh
		helm init --client-only
	fi
}



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

function testDeploy() {
	local appName
	appName=$(retrieveAppName)
	# Log in to PaaS to start deployment
	logInToPaas
	setVersionForReleaseTrain "${appName}" "${PIPELINE_VERSION}"
	deployServices

	# deploy app
	deployAndRestartAppWithNameForSmokeTests "${appName}" "${PIPELINE_VERSION}"
}

function testRollbackDeploy() {
	rm -rf "${OUTPUT_FOLDER}/test.properties"
	local latestProdTag="${1}"
	local appName
	appName=$(retrieveAppName)
	local latestProdVersion
	latestProdVersion="${latestProdTag#prod/}"
	echo "Last prod version equals ${latestProdVersion}"
	logInToPaas
	parsePipelineDescriptor

	deployAndRestartAppWithNameForSmokeTests "${appName}" "${latestProdVersion}"

	# Adding latest prod tag
	echo "LATEST_PROD_TAG=${latestProdTag}" >>"${OUTPUT_FOLDER}/test.properties"
}

function deployService() {
	local serviceType
	serviceType="$(toLowerCase "${1}")"
	local serviceName
	serviceName="${2}"
	local serviceCoordinates
	serviceCoordinates="$(if [[ "${3}" == "null" ]]; then
		echo "";
	else
		echo "${3}";
	fi)"
	local coordinatesSeparator=":"
	echo "Will deploy service with type [${serviceType}] name [${serviceName}] and coordinates [${serviceCoordinates}]"
	case ${serviceType} in
		configserver)
			deployConfigServer "${serviceName}"
		;;
        otherservices)
			deployOtherServices "${serviceName}"
        ;;
		claim-contracts)
			deploy_project  "https://github.com/asokjp/claim-contracts1"
			;;
		anthem-microservices-starter-build)
			#deploy_project  "https://github.com/asokjp/anthem-microservices-starter-build"
		;;
		*)
			echo "Unknown service [${serviceType}]"
			return 1
		;;
	esac
}

function deploy_project {
	local project_repo="$1"
	local project_name

	project_name="$( basename "${project_repo}" )"

	echo "Deploying ${project_name} to artifactory"
	PROJECT_PARENT_PATH="${HOME}/${project_name}"
	mkdir "${project_name}"
	pushd "${project_name}"
	rm -rf "${project_name}"
	git clone "${project_repo}" && cd "${project_name}"
	chmod a+x mvnw
	./mvnw clean install 
	popd
}

function configServerName() {
 echo "${PARSED_YAML}" | jq --arg x "${LOWERCASE_ENV}" '.[$x].services[] | select(.type == "configserver") | .name' | sed 's/^"\(.*\)"$/\1/' || echo ""
}


function eurekaName() {
	echo "${PARSED_YAML}" | jq --arg x "${LOWERCASE_ENV}" '.[$x].services[] | select(.type == "eureka") | .name' | sed 's/^"\(.*\)"$/\1/' || echo ""
}

function rabbitMqName() {
	echo "${PARSED_YAML}" | jq --arg x "${LOWERCASE_ENV}" '.[$x].services[] | select(.type == "rabbitmq") | .name' | sed 's/^"\(.*\)"$/\1/' || echo ""
}

function mySqlName() {
	echo "${PARSED_YAML}" | jq --arg x "${LOWERCASE_ENV}" '.[$x].services[] | select(.type == "mysql") | .name' | sed 's/^"\(.*\)"$/\1/' || echo ""
}

function mySqlDatabase() {
	echo "${PARSED_YAML}" | jq --arg x "${LOWERCASE_ENV}" '.[$x].services[] | select(.type == "mysql") | .database' | sed 's/^"\(.*\)"$/\1/' || echo ""
}

function appSystemProps() {
	local systemProps
	systemProps=""
	# TODO: Not every system needs Eureka or Rabbit. But we need to bind this somehow...
	local eurekaName
	eurekaName="$(eurekaName)"
	local rabbitMqName
	rabbitMqName="$(rabbitMqName)"
	local mySqlName
	mySqlName="$(mySqlName)"
	local mySqlDatabase
}

function deleteService() {
	local serviceType="${1}"
	local serviceName="${2}"
	echo "Deleting all possible entries with name [${serviceName}]"
	deleteAppByName "${serviceName}"
}

function deployConfigServer() {
local serviceName="${1:-config-server}"
	local objectDeployed
	objectDeployed="$(objectDeployed "service" "${serviceName}")"
	if [[ "${ENVIRONMENT}" == "STAGE" && "${objectDeployed}" == "true" ]]; then
		echo "Service [${serviceName}] already deployed. Won't redeploy for stage"
		return
	fi
	echo "Waiting for configserver to start"
	local originalDeploymentFile="${__ROOT}/k8s/configserver.yml"
	local outputDirectory
	outputDirectory="$(outputFolder)/k8s"
	mkdir -p "${outputDirectory}"
	cp "${originalDeploymentFile}" "${outputDirectory}"
	local deploymentFile="${outputDirectory}/configserver.yml"
	if [[ "${ENVIRONMENT}" == "TEST" ]]; then
		deleteAppByFile "${deploymentFile}"
	fi
	replaceApp "${deploymentFile}"
}

function deployOtherServices() {
local serviceName="${1:-other-services}"
	local objectDeployed
	objectDeployed="$(objectDeployed "service" "${serviceName}")"
	if [[ "${ENVIRONMENT}" == "STAGE" && "${objectDeployed}" == "true" ]]; then
		echo "Service [${serviceName}] already deployed. Won't redeploy for stage"
		return
	fi
	echo "Waiting for configserver to start"
	local originalDeploymentFile="${__ROOT}/k8s/poc1.yml"
	local outputDirectory
	outputDirectory="$(outputFolder)/k8s"
	mkdir -p "${outputDirectory}"
	cp "${originalDeploymentFile}" "${outputDirectory}"
	local deploymentFile="${outputDirectory}/poc1.yml"
	if [[ "${ENVIRONMENT}" == "TEST" ]]; then
		deleteAppByFile "${deploymentFile}"
	fi
	replaceApp "${deploymentFile}"
}


function deployRabbitMq() {
	local serviceName="${1:-rabbitmq-github}"
	local objectDeployed
	objectDeployed="$(objectDeployed "service" "${serviceName}")"
	if [[ "${ENVIRONMENT}" == "STAGE" && "${objectDeployed}" == "true" ]]; then
		echo "Service [${serviceName}] already deployed. Won't redeploy for stage"
		return
	fi
	echo "Waiting for RabbitMQ to start"
	local originalDeploymentFile="${__ROOT}/k8s/rabbitmq.yml"
	local originalServiceFile="${__ROOT}/k8s/rabbitmq-service.yml"
	local outputDirectory
	outputDirectory="$(outputFolder)/k8s"
	mkdir -p "${outputDirectory}"
	cp "${originalDeploymentFile}" "${outputDirectory}"
	cp "${originalServiceFile}" "${outputDirectory}"
	local deploymentFile="${outputDirectory}/rabbitmq.yml"
	local serviceFile="${outputDirectory}/rabbitmq-service.yml"
	substituteVariables "appName" "${serviceName}" "${deploymentFile}"
	substituteVariables "appName" "${serviceName}" "${serviceFile}"
	if [[ "${ENVIRONMENT}" == "TEST" ]]; then
		deleteAppByFile "${deploymentFile}"
		deleteAppByFile "${serviceFile}"
	fi
	replaceApp "${deploymentFile}"
	replaceApp "${serviceFile}"
}

function deployApp() {
	local fileName="${1}"
	"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" create -f "${fileName}"
}

function replaceApp() {
	local fileName="${1}"
	"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" replace --force -f "${fileName}"
}

function deleteAppByName() {
	local serviceName="${1}"
	"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" delete secret "${serviceName}" || result=""
	"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" delete persistentvolumeclaim "${serviceName}" || result=""
	"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" delete pod "${serviceName}" || result=""
	"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" delete deployment "${serviceName}" || result=""
	"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" delete service "${serviceName}" || result=""
}

function deleteAppByFile() {
	local file="${1}"
	"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" delete -f "${file}" || echo "Failed to delete app by [${file}] file. Continuing with the script"
}

function system {
	local unameOut
	unameOut="$(uname -s)"
	case "${unameOut}" in
		Linux*) machine=linux ;;
		Darwin*) machine=darwin ;;
		*) echo "Unsupported system" && exit 1
	esac
	echo "${machine}"
}

function setVersionForReleaseTrain() {
	local projectName = "${1}"
	echo "project name is ${1}"
	version = "${2}"
	echo "version is ${version}"
	git clone https://github.com/asokjp/prod-env-deploy
	#git add "${deploymentFile}"
	git add *
	git commit -m "adding new version"
	git push orgin master
	local variableName = "${1}-version"
	echo "variableName is ${variableName}"
	local deploymentFile="prod-env-deploy/releasetrain.yml"
	substituteVariables "${variableName}" "${version}" "${deploymentFile}"
}

function substituteVariables() {
	local variableName="${1}"
	local substitution="${2}"
	local fileName="${3}"
	local escapedSubstitution
	escapedSubstitution=$(escapeValueForSed "${substitution}")
	#echo "Changing [${variableName}] -> [${escapedSubstitution}] for file [${fileName}]"
	if [[ "${SYSTEM}" == "darwin" ]]; then
		sed -i "" "s/{{${variableName}}}/${escapedSubstitution}/" "${fileName}"
	else
		sed -i "s/{{${variableName}}}/${escapedSubstitution}/" "${fileName}"
	fi
}

function deployMySql() {
	local serviceName="${1:-mysql-github}"
	local objectDeployed
	objectDeployed="$(objectDeployed "service" "${serviceName}")"
	if [[ "${ENVIRONMENT}" == "STAGE" && "${objectDeployed}" == "true" ]]; then
		echo "Service [${serviceName}] already deployed. Won't redeploy for stage"
		return
	fi
	local secretName
	secretName="mysql-$(retrieveAppName)"
	echo "Waiting for MySQL to start"
	local originalDeploymentFile="${__ROOT}/k8s/mysql.yml"
	local originalServiceFile="${__ROOT}/k8s/mysql-service.yml"
	local outputDirectory
	outputDirectory="$(outputFolder)/k8s"
	mkdir -p "${outputDirectory}"
	cp "${originalDeploymentFile}" "${outputDirectory}"
	cp "${originalServiceFile}" "${outputDirectory}"
	local deploymentFile="${outputDirectory}/mysql.yml"
	local serviceFile="${outputDirectory}/mysql-service.yml"
	local mySqlDatabase
	mySqlDatabase="$(mySqlDatabase)"
	echo "Generating secret with name [${secretName}]"
	"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" delete secret "${secretName}" || echo "Failed to delete secret [${serviceName}]. Continuing with the script"
	"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" create secret generic "${secretName}" --from-literal=username="${MYSQL_USER}" --from-literal=password="${MYSQL_PASSWORD}" --from-literal=rootpassword="${MYSQL_ROOT_PASSWORD}"
	substituteVariables "appName" "${serviceName}" "${deploymentFile}"
	substituteVariables "secretName" "${secretName}" "${deploymentFile}"
	substituteVariables "mysqlDatabase" "${mySqlDatabase}" "${deploymentFile}"
	substituteVariables "appName" "${serviceName}" "${serviceFile}"
	if [[ "${ENVIRONMENT}" == "TEST" ]]; then
		deleteAppByFile "${deploymentFile}"
		deleteAppByFile "${serviceFile}"
	fi
	replaceApp "${deploymentFile}"
	replaceApp "${serviceFile}"
}

function findAppByName() {
	local serviceName
	serviceName="${1}"
	"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" get pods -o wide -l app="${serviceName}" | awk -v "app=${serviceName}" '$1 ~ app {print($0)}'
}

function deployAndRestartAppWithName() {
	local appName="${1}"
	local jarName="${2}"
	local env="${LOWERCASE_ENV}"
	echo "Deploying and restarting app with name [${appName}] and jar name [${jarName}]"
	deployAppWithName "${appName}" "${jarName}" "${env}" 'true'
	restartApp "${appName}"
}

function deployAndRestartAppWithNameForSmokeTests() {
	local appName="${1}"
	local version="${2}"
	local profiles="smoke,kubernetes"
	local lowerCaseAppName
	lowerCaseAppName=$(toLowerCase "${appName}")
	local originalDeploymentFile="deployment.yml"
	local originalServiceFile="service.yml"
	local outputDirectory
	outputDirectory="$(outputFolder)/k8s"
	mkdir -p "${outputDirectory}"
	cp "${originalDeploymentFile}" "${outputDirectory}"
	cp "${originalServiceFile}" "${outputDirectory}"
	local deploymentFile="${outputDirectory}/deployment.yml"
	local serviceFile="${outputDirectory}/service.yml"
	local systemProps
	systemProps="-Dspring.profiles.active=${profiles} $(appSystemProps)"
	substituteVariables "dockerOrg" "${DOCKER_REGISTRY_ORGANIZATION}" "${deploymentFile}"
	substituteVariables "version" "${version}" "${deploymentFile}"
	substituteVariables "appName" "${appName}" "${deploymentFile}"
	substituteVariables "labelAppName" "${appName}" "${deploymentFile}"
	substituteVariables "containerName" "${appName}" "${deploymentFile}"
	substituteVariables "systemProps" "${systemProps}" "${deploymentFile}"
	substituteVariables "appName" "${appName}" "${serviceFile}"
	deleteAppByFile "${deploymentFile}"
	deleteAppByFile "${serviceFile}"
	deployApp "${deploymentFile}"
	deployApp "${serviceFile}"
	waitForAppToStart "${appName}"
}

function deployAndRestartAppWithNameForE2ETests() {
	local appName="${1}"
	local profiles="e2e,kubernetes"
	local lowerCaseAppName
	lowerCaseAppName=$(toLowerCase "${appName}")
	local originalDeploymentFile="deployment.yml"
	local originalServiceFile="service.yml"
	local outputDirectory
	outputDirectory="$(outputFolder)/k8s"
	mkdir -p "${outputDirectory}"
	cp "${originalDeploymentFile}" "${outputDirectory}"
	cp "${originalServiceFile}" "${outputDirectory}"
	local deploymentFile="${outputDirectory}/deployment.yml"
	local serviceFile="${outputDirectory}/service.yml"
	local systemProps="-Dspring.profiles.active=${profiles}"
	substituteVariables "dockerOrg" "${DOCKER_REGISTRY_ORGANIZATION}" "${deploymentFile}"
	substituteVariables "version" "${PIPELINE_VERSION}" "${deploymentFile}"
	substituteVariables "appName" "${appName}" "${deploymentFile}"
	substituteVariables "labelAppName" "${appName}" "${deploymentFile}"
	substituteVariables "containerName" "${appName}" "${deploymentFile}"
	substituteVariables "systemProps" "${systemProps}" "${deploymentFile}"
	substituteVariables "appName" "${appName}" "${serviceFile}"
	deleteAppByFile "${deploymentFile}"
	deleteAppByFile "${serviceFile}"
	deployApp "${deploymentFile}"
	deployApp "${serviceFile}"
	waitForAppToStart "${appName}"
}

function toLowerCase() {
	local string=${1}
	echo "${string}" | tr '[:upper:]' '[:lower:]'
}

function lowerCaseEnv() {
	echo "${ENVIRONMENT}" | tr '[:upper:]' '[:lower:]'
}

function deleteAppInstance() {
	local serviceName="${1}"
	local lowerCaseAppName
	lowerCaseAppName=$(toLowerCase "${serviceName}")
	echo "Deleting application [${lowerCaseAppName}]"
	deleteAppByName "${lowerCaseAppName}"
}

function deployEureka() {
	local imageName="${1}"
	local appName="${2}"
	local objectDeployed
	objectDeployed="$(objectDeployed "service" "${appName}")"
	if [[ "${ENVIRONMENT}" == "STAGE" && "${objectDeployed}" == "true" ]]; then
		echo "Service [${appName}] already deployed. Won't redeploy for stage"
		return
	fi
	echo "Deploying Eureka. Options - image name [${imageName}], app name [${appName}], env [${ENVIRONMENT}]"
	local originalDeploymentFile="${__ROOT}/k8s/eureka.yml"
	local originalServiceFile="${__ROOT}/k8s/eureka-service.yml"
	local outputDirectory
	outputDirectory="$(outputFolder)/k8s"
	mkdir -p "${outputDirectory}"
	cp "${originalDeploymentFile}" "${outputDirectory}"
	cp "${originalServiceFile}" "${outputDirectory}"
	local deploymentFile="${outputDirectory}/eureka.yml"
	local serviceFile="${outputDirectory}/eureka-service.yml"
	substituteVariables "appName" "${appName}" "${deploymentFile}"
	substituteVariables "appUrl" "${appName}.${PAAS_NAMESPACE}" "${deploymentFile}"
	substituteVariables "eurekaImg" "${imageName}" "${deploymentFile}"
	substituteVariables "appName" "${appName}" "${serviceFile}"
	if [[ "${ENVIRONMENT}" == "TEST" ]]; then
		deleteAppByFile "${deploymentFile}"
		deleteAppByFile "${serviceFile}"
	fi
	replaceApp "${deploymentFile}"
	replaceApp "${serviceFile}"
	waitForAppToStart "${appName}"
}

function escapeValueForSed() {
	echo "${1//\//\\/}"
}

function deployStubRunnerBoot() {
	local imageName="${1}"
	local repoWithJars="${2}"
	local rabbitName="${3}.${PAAS_NAMESPACE}"
	local eurekaName="${4}.${PAAS_NAMESPACE}"
	local stubRunnerName="${5:-stubrunner}"
	local stubRunnerUseClasspath="${stubRunnerUseClasspath:-false}"
	echo "Deploying Stub Runner. Options - image name [${imageName}], app name [${stubRunnerName}]"
	local stubrunnerIds
	stubrunnerIds="$(retrieveStubRunnerIds)"
	echo "Found following stub runner ids [${stubrunnerIds}]"
	local originalDeploymentFile="${__ROOT}/k8s/stubrunner.yml"
	local originalServiceFile="${__ROOT}/k8s/stubrunner-service.yml"
	local outputDirectory
	outputDirectory="$(outputFolder)/k8s"
	local systemProps=""
	mkdir -p "${outputDirectory}"
	cp "${originalDeploymentFile}" "${outputDirectory}"
	cp "${originalServiceFile}" "${outputDirectory}"
	local deploymentFile="${outputDirectory}/stubrunner.yml"
	local serviceFile="${outputDirectory}/stubrunner-service.yml"
	if [[ "${stubRunnerUseClasspath}" == "false" ]]; then
		systemProps="${systemProps} -Dstubrunner.repositoryRoot=${repoWithJars}"
	fi
	substituteVariables "appName" "${stubRunnerName}" "${deploymentFile}"
	substituteVariables "stubrunnerImg" "${imageName}" "${deploymentFile}"
	substituteVariables "systemProps" "${systemProps}" "${deploymentFile}"
	substituteVariables "rabbitAppName" "${rabbitName}" "${deploymentFile}"
	substituteVariables "eurekaAppName" "${eurekaName}" "${deploymentFile}"
	if [[ "${stubrunnerIds}" != "" ]]; then
		substituteVariables "stubrunnerIds" "${stubrunnerIds}" "${deploymentFile}"
	else
		substituteVariables "stubrunnerIds" "" "${deploymentFile}"
	fi
	substituteVariables "appName" "${stubRunnerName}" "${serviceFile}"
	if [[ "${ENVIRONMENT}" == "TEST" ]]; then
		deleteAppByFile "${deploymentFile}"
		deleteAppByFile "${serviceFile}"
	fi
	replaceApp "${deploymentFile}"
	replaceApp "${serviceFile}"
	waitForAppToStart "${stubRunnerName}"
}

function prepareForSmokeTests() {
	echo "Retrieving group and artifact id - it can take a while..."
	local appName
	appName="$(retrieveAppName)"
	mkdir -p "${OUTPUT_FOLDER}"
	logInToPaas
	local applicationPort
	applicationPort="$(portFromKubernetes "${appName}")"
	#local stubrunnerAppName
	#stubrunnerAppName="stubrunner-${appName}"
	#local stubrunnerPort
	#stubrunnerPort="$(portFromKubernetes "${stubrunnerAppName}")"
	local applicationHost
	applicationHost="$(applicationHost "${appName}")"
	#local stubRunnerUrl
	#stubRunnerUrl="$(applicationHost "${stubrunnerAppName}")"
	echo "application url: ${applicationHost}:${applicationPort}"
	export APPLICATION_URL="${applicationHost}:${applicationPort}"
	#export STUBRUNNER_URL="${stubRunnerUrl}:${stubrunnerPort}"
}

function prepareForE2eTests() {
	echo "Retrieving group and artifact id - it can take a while..."
	local appName
	appName="$(retrieveAppName)"
	mkdir -p "${OUTPUT_FOLDER}"
	logInToPaas
	local applicationPort
	applicationPort="$(portFromKubernetes "${appName}")"
	local applicationHost
	applicationHost="$(applicationHost "${appName}")"
	export APPLICATION_URL="${applicationHost}:${applicationPort}"
}

function applicationHost() {
	local appName="${1}"
	if [[ "${KUBERNETES_MINIKUBE}" == "true" ]]; then
		local apiUrlProp="PAAS_${ENVIRONMENT}_API_URL"
		# host:port -> host
		echo "${!apiUrlProp}" | awk -F: '{print $1}'
	else
		echo "${appName}.${PAAS_NAMESPACE}"
	fi
}

function portFromKubernetes() {
	local appName="${1}"
	local jsonPath
	{ if [[ "${KUBERNETES_MINIKUBE}" == "true" ]]; then
		jsonPath="{.spec.ports[0].nodePort}"
	else
		jsonPath="{.spec.ports[0].port}"
	fi
	}
	# '8080' -> 8080
	"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" get svc "${appName}" -o jsonpath="${jsonPath}"
}

function waitForAppToStart() {
	local appName="${1}"
	local port
	port="$(portFromKubernetes "${appName}")"
	local applicationHost
	applicationHost="$(applicationHost "${appName}")"
	echo "application host is - ${applicationHost}" 
	isAppRunning "${applicationHost}" "${port}"
}

function retrieveApplicationUrl() {
	local appName
	appName="$(retrieveAppName)"
	local port
	port="$(portFromKubernetes "${appName}")"
	local kubHost
	kubHost="$(applicationHost "${appName}")"
	echo "${kubHost}:${port}"
}

function isAppRunning() {
	local host="${1}"
	local port="${2}"
	local waitTime=5
	local retries=50
	local running=1
	local healthEndpoint="health"
	echo "Checking if app [${host}:${port}] is running at [/${healthEndpoint}] endpoint"
	for i in $(seq 1 "${retries}"); do
		curl -m 5 "${host}:${port}/${healthEndpoint}" && running=0 && break
		echo "Fail #$i/${retries}... will try again in [${waitTime}] seconds"
		sleep "${waitTime}"
	done
	if [[ "${running}" == 1 ]]; then
		echo "App failed to start"
		exit 1
	fi
	echo ""
	echo "App started successfully!"
}

function readTestPropertiesFromFile() {
	local fileLocation="${1:-${OUTPUT_FOLDER}/test.properties}"
	local key
	local value
	if [ -f "${fileLocation}" ]
	then
		echo "${fileLocation} found."
		while IFS='=' read -r key value
		do
			key="$(echo "${key}" | tr '.' '_')"
			eval "${key}='${value}'"
		done <"${fileLocation}"
	else
		echo "${fileLocation} not found."
	fi
}

function label() {
	local appName="${1}"
	local key="${2}"
	local value="${3}"
	local type="deployment"
	"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" label "${type}" "${appName}" "${key}"="${value}"
}

function objectDeployed() {
	local appType="${1}"
	local appName="${2}"
	local result
	result="$("${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" get "${appType}" "${appName}" --ignore-not-found=true)"
	if [[ "${result}" != "" ]]; then
		echo "true"
	else
		echo "false"
	fi
}

function stageDeploy() {
	local appName
	appName="$(retrieveAppName)"
	# Log in to PaaS to start deployment
	logInToPaas

	deployServices

	# deploy app
	deployAndRestartAppWithNameForE2ETests "${appName}"
}

function performGreenDeployment() {
	# TODO: Consider making it less JVM specific
	#local appName
	#appName="$(retrieveAppName)"
	# Log in to PaaS to start deployment
	logInToPaas

	# deploy app
	performGreenDeploymentOfTestedApplication "${appName}"
}

function performGreenDeploymentOfConfigServer() {
	local appName="config-server"
	helm install  --set configserver.image.name="${DOCKER_REGISTRY_ORGANIZATION}/${appName}/${PIPELINE_VERSION}" --name "London" --namespace  ./configserver
	waitForAppToStart "${appName}"
	
}


function performGreenDeploymentOfTestedApplication() {
	local appName="${1}"
	local lowerCaseAppName
	lowerCaseAppName=$(toLowerCase "${appName}")
	local profiles="kubernetes"
	local originalDeploymentFile="deployment.yml"
	local originalServiceFile="service.yml"
	local outputDirectory
	outputDirectory="$(outputFolder)/k8s"
	mkdir -p "${outputDirectory}"
	cp "${originalDeploymentFile}" "${outputDirectory}"
	cp "${originalServiceFile}" "${outputDirectory}"
	local deploymentFile="${outputDirectory}/deployment.yml"
	local serviceFile="${outputDirectory}/service.yml"
	local changedAppName
	changedAppName="$(escapeValueForDns "${appName}-${PIPELINE_VERSION}")"
	echo "Will name the application [${changedAppName}]"
	local otherDeployedInstances
	otherDeployedInstances="$(otherDeployedInstances "${appName}" "${changedAppName}")"
	if [[ "${otherDeployedInstances}" != "" ]]; then
		local numberOfDeployments
		numberOfDeployments="$(echo "${otherDeployedInstances}" | wc -l | awk '{print $1}')"
		if ((numberOfDeployments > 1)); then
			echo "Green already deployed. Please complete switch over first"
			return 1
		fi
	fi
	local systemProps="-Dspring.profiles.active=${profiles}"
	substituteVariables "dockerOrg" "${DOCKER_REGISTRY_ORGANIZATION}" "${deploymentFile}"
	substituteVariables "version" "${PIPELINE_VERSION}" "${deploymentFile}"
	# The name will contain also the version
	substituteVariables "labelAppName" "${changedAppName}" "${deploymentFile}"
	substituteVariables "appName" "${appName}" "${deploymentFile}"
	substituteVariables "containerName" "${appName}" "${deploymentFile}"
	substituteVariables "systemProps" "${systemProps}" "${deploymentFile}"
	substituteVariables "appName" "${appName}" "${serviceFile}"
	deployApp "${deploymentFile}"
	local serviceDeployed
	serviceDeployed="$(objectDeployed "service" "${appName}")"
	echo "Service already deployed? [${serviceDeployed}]"
	if [[ "${serviceDeployed}" == "false" ]]; then
		deployApp "${serviceFile}"
	fi
	waitForAppToStart "${appName}"
}

function escapeValueForDns() {
	local sed
	sed="$(sed -e 's/\./-/g;s/_/-/g' <<<"$1")"
	local lowerCaseSed
	lowerCaseSed="$(toLowerCase "${sed}")"
	echo "${lowerCaseSed}"
}

function rollbackToPreviousVersion() {
	local appName
	appName="$(retrieveAppName)"
	# Log in to CF to start deployment
	logInToPaas
	local changedAppName
	changedAppName="$( dnsEscapedAppNameWithVersionSuffix "${appName}-${PIPELINE_VERSION}")"
	# find the oldest version and remove it
	local oldestDeployment
	oldestDeployment="$(oldestDeployment "${appName}" "${changedAppName}")"
	if [[ "${oldestDeployment}" != "" ]]; then
		echo "Scaling the green instance to 0 instances. Only blue instance will be running"
		"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" scale deployment "${changedAppName}" --replicas=0
	else
		echo "Will not rollback to blue instance cause it's not there"
		return 1
	fi
}

function deleteBlueInstance() {
	local appName
	appName="$(retrieveAppName)"
	# Log in to CF to start deployment
	logInToPaas
	# find the oldest version and remove it
	local changedAppName
	changedAppName="$(dnsEscapedAppNameWithVersionSuffix "${appName}-${PIPELINE_VERSION}")"
	local otherDeployedInstances
	otherDeployedInstances="$(otherDeployedInstances "${appName}" "${changedAppName}" )"
	local oldestDeployment
	oldestDeployment="$(oldestDeployment "${otherDeployedInstances}")"
	if [[ "${oldestDeployment}" != "" ]]; then
		echo "Deleting deployment with name [${oldestDeployment}]"
		"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" delete deployment "${oldestDeployment}"
	else
		echo "There's no blue instance to remove, skipping this step"
	fi
}

function otherDeployedInstances() {
	local appName="${1}"
	local changedAppName="${2}"
	"${KUBECTL_BIN}" --context="${K8S_CONTEXT}" --namespace="${PAAS_NAMESPACE}" get deployments -lname="${appName}" --no-headers | awk '{print $1}' | grep -v "${changedAppName}" || echo ""
}

function oldestDeployment() {
	local deployedApps
	deployedApps="${1}"
	local oldestDeployment
	oldestDeployment="$(echo "${deployedApps}" | sort | head -n 1)"
	echo "${oldestDeployment}"
}

function dnsEscapedAppNameWithVersionSuffix() {
	local appName="${1}"
	escapeValueForDns "${appName}"
}

__ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PAAS_NAMESPACE_VAR="PAAS_${ENVIRONMENT}_NAMESPACE"
[[ -z "${PAAS_NAMESPACE}" ]] && PAAS_NAMESPACE="${!PAAS_NAMESPACE_VAR}"
export KUBERNETES_NAMESPACE="${PAAS_NAMESPACE}"
export SYSTEM
SYSTEM="$(system)"
export KUBE_CONFIG_PATH
KUBE_CONFIG_PATH="${KUBE_CONFIG_PATH}"
if [[ ! -z "${KUBE_CONFIG_PATH}" ]]; then
	KUBE_CONFIG_PATH="$(mktemp -d 2>/dev/null || mktemp -d -t 'sc-pipelines-k8s')"
	trap '{ rm -rf ${KUBE_CONFIG_PATH}; }' EXIT
fi
export KUBECTL_BIN
KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"

# We need to pass additional, Docker related options to the build
DEFAULT_DOCKER_OPTIONS="-DDOCKER_REGISTRY_ORGANIZATION=${DOCKER_REGISTRY_ORGANIZATION} -DDOCKER_REGISTRY_URL=${DOCKER_REGISTRY_URL} -DDOCKER_SERVER_ID=${DOCKER_SERVER_ID} -DDOCKER_USERNAME=${DOCKER_USERNAME} -DDOCKER_PASSWORD=${DOCKER_PASSWORD} -DDOCKER_EMAIL=${DOCKER_EMAIL}"
if [[ ! -z ${BUILD_OPTIONS} && ${BUILD_OPTIONS} != "null" ]]; then
	export BUILD_OPTIONS="${BUILD_OPTIONS} ${DEFAULT_DOCKER_OPTIONS}"
else
	export BUILD_OPTIONS="${DEFAULT_DOCKER_OPTIONS}"
fi

# CURRENTLY WE ONLY SUPPORT JVM BASED PROJECTS OUT OF THE BOX
# shellcheck source=/dev/null
[[ -f "${__ROOT}/projectType/pipeline-jvm.sh" ]] && source "${__ROOT}/projectType/pipeline-jvm.sh" ||  \
 echo "No projectType/pipeline-jvm.sh found"
