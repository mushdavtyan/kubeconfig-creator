#!/bin/bash

#This script will generate 1 read and 1 full permission kubeconfigs for correspondig users synisys-read and synisys-admin


declare -a user_permissions=("user-admin:cluster-admin" "user-read:view")

TARGET_FOLDER="/opt/kubeconfigs"
NAMESPACE="kube-system"
KUBECONF="/etc/kubernetes/admin.conf"

######################## Describing functions ###############################



if [ ! -z "$1" ]
then
    CLUSTER_NAME=$1
else
    CLUSTER_NAME=`hostname | sed -e 's/k8s//'| sed -e 's/kube//' | sed -e 's/worker//' | sed -e 's/node//' | sed -e 's/master//' | sed -e 's/-//' | sed -e 's/-//'`
fi
CLUSTER_CA_DATA=$(cat $KUBECONF | grep certificate-authority-data: | awk '{print $2}')
CLUSTER_SERVER=`cat /etc/kubernetes/kubelet.conf | grep server | awk '{print $2}'`

ld=$(tput bold)
underline=$(tput sgr 0 1)
reset=$(tput sgr0)
purple=$(tput setaf 171)
red=$(tput setaf 1)
green=$(tput setaf 76)
tan=$(tput setaf 3)
blue=$(tput setaf 38)

e_header() { printf "${bold}${purple}==========  %s  ==========${reset}\n\n" "$@" 
}
e_arrow() { printf "${bold}➜ %s${reset}\n\n" "$@"
}
e_success() { printf "${green}✔ %s${reset}\n" "$@"
}
e_error() { printf "${red}✖ %s${reset}\n" "$@"
}
e_purple() { printf "${purple}➜ %s${reset}\n" "$@"
}

function Create_Target_Folder() {
    if [[ ! -d "${TARGET_FOLDER}" ]]
    then 
        mkdir -p "${TARGET_FOLDER}"
        e_success "Created target directory to hold files in ${TARGET_FOLDER}..."
    else
        e_success "Folder ${TARGET_FOLDER} is already exits. Skipping..."
    fi
}

function Create_Service_Account() {
    GET_SA=$(kubectl --kubeconfig="${KUBECONF}" get sa -n "${NAMESPACE}" | grep -w "${1}" | awk '{print $1}')
    if [[ ! "${GET_SA}" == "${1}" ]]
    then
        kubectl --kubeconfig=$KUBECONF create sa $1 --namespace "${NAMESPACE}" > /dev/null
        e_success "Created a service account for the user $1"
    else
        e_success "Serviceaccount $1 is already exist. Skipping..."
    fi
}

function Create_RBAC_Clusterrolebinding() {
    GET_CLUSTERROLEBINDING=$(kubectl --kubeconfig="${KUBECONF}" get clusterrolebinding | grep -w "${1}" | awk '{print $1}')
    if [[ ! "${GET_CLUSTERROLEBINDING}" == "${1}" ]]
    then
        kubectl --kubeconfig="${KUBECONF}" create clusterrolebinding "${1}" --clusterrole="${2}" --serviceaccount="${NAMESPACE}":"${1}" > /dev/null
        e_success "Created RBAC clusterrolebinding for user $1 with $2 permissions"
    else
        e_success "Clusterrolebinding for serviceaccount $1 is already exist. Skipping..."
    fi
}

function  Get_Token() {
    USER_TOKEN_NAME=$(kubectl --kubeconfig="${KUBECONF}" -n "${NAMESPACE}" get serviceaccount $1 -o=jsonpath='{.secrets[0].name}')
    USER_TOKEN_VALUE=$(kubectl --kubeconfig="${KUBECONF}" -n "${NAMESPACE}" get secret/${USER_TOKEN_NAME} -o=go-template='{{.data.token}}' | base64 --decode)
    e_success "Grabbed token of serviceaccount $1"
}

function Check_kubeconfig() {
    e_success "Checking generated kubeconfig for $2 privileges"
    if [[ $2 == "read" ]]
    then
        CAN_I=$(kubectl auth --kubeconfig "${TARGET_FOLDER}"/"${CLUSTER_NAME}"-"${1}" can-i get po -n kube-system)
    elif [[ $2 == "cluster-admin" ]]
    then
        CAN_I=$(kubectl auth --kubeconfig "${TARGET_FOLDER}"/"${CLUSTER_NAME}"-"${1}" can-i delete po -n kube-system)
    fi

    if [[ ! "CAN_I" == "yes" ]]
    then
        return 0
    else
        return 1
    fi
}

Generate_Kubeconfig () {
cat <<-EOF > ${TARGET_FOLDER}/${CLUSTER_NAME}-${1}
apiVersion: v1
kind: Config
current-context: ${CLUSTER_NAME}
contexts:
- name: ${CLUSTER_NAME}
  context:
    cluster: ${CLUSTER_NAME}
    user: $1
    namespace: ${NAMESPACE}
clusters:
- name: ${CLUSTER_NAME}
  cluster:
    certificate-authority-data: ${CLUSTER_CA_DATA}
    server: ${CLUSTER_SERVER}
users:
- name: $1
  user:
    token: ${USER_TOKEN_VALUE}
EOF
e_success "Generated kubeconfig and stored on ${TARGET_FOLDER}/${CLUSTER_NAME}-${1}"
} 

############# Starting the script #####################

e_header  "Starting the script"
sleep 1

Create_Target_Folder

for value in "${user_permissions[@]}"
do
    USER="${value%%:*}"
    CLUSTERROLE="${value##*:}"
    echo ""
    e_purple "Starting gererate kubeconfig for $USER with $CLUSTERROLE privileges"

    Create_Service_Account "${USER}" "${CLUSTERROLE}"
    Create_RBAC_Clusterrolebinding "${USER}" "${CLUSTERROLE}"
    Get_Token "${USER}" 
    Generate_Kubeconfig "${USER}"


    if Check_kubeconfig "${USER}" "${CLUSTERROLE}"
    then
        e_success "${TARGET_FOLDER}/${CLUSTER_NAME}-${USER} kubeconfig was checked. It's functional and working"
        continue
    else
        e_error "Created kubeconfig for user $USER is not working. Stoping script..."
        exit 1
    fi
done


e_header "Kubeconfig generation scipt successfully completed his job"
e_arrow "Please find gererated kubeconfigs on folder ${TARGET_FOLDER}"
