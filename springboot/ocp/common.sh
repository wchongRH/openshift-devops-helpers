#!/usr/bin/env bash

# this script is meant to be sourced from main scripts

# ----------------------------------------------------
# Helper functions

function check_error() {
    local label="$1"
    local error="$2"
    if [ ${error} -ne 0 ]; then
        echo "Aborting due to error code $error for $label"
        exit ${error}
    fi
}

function cleanup() {
    set +x +e
    oc_logout
}

function oc_login() {
    local url="$1"
    local role="$2"
    local token="$3"
    local pushtoextregtimeout="$4"
   
    oc login --insecure-skip-tls-verify --config=${TMP_DIR}/${role}.config --token=${token} ${url} &> /dev/null
    check_error "login to ${url}" $?
    if [[ -z $pushtoextregtimeout || $pushtoextregtimeout == "null" ]];then
    echo "oc --config=${TMP_DIR}/${role}.config $OPENSHIFT_CLI_OPTIONS"
    else
    echo "oc --config=${TMP_DIR}/${role}.config $OPENSHIFT_CLI_EXT_REG_OPTIONS"
    fi
}


#Actual log out from OCP is prevented for now as the token provided by AXA will be invalidated immediately on log out. As of 20181112, AXA is still working on a different token-provisioning system that avoids this condition.
function oc_logout() {
	echo -e "\n### Logging out #############\n";
	for f in $TMP_DIR/*.config; do
	#	oc logout --config=$f &&
                rm -f $f # should be in logout line separated temporarily ao avoid single logout problem
	done
}


#####################################
# AXA implemented OpenPAAS, a business service to monetize their OCP.
# The following "ap"-prefixed functions helper functions were
# implemented by Red Hat to facilitate the use of OpenPAAS
####################################

# Calls the AXA OpenPAAS API to perform either a "DELETE project" or "GET project status" request.
# Valid ACTIONs are "GET" and "DELETE"
# This function writes the response from OpenPAAS to a file named status.out
function ap_project_action () {
local PROJECT_ID=$1
local TOKEN=$2
local ACTION=$3
curl -k -v -X $ACTION -o status.out "$GATEWAY/$PROJECT_ID" -H "Accept: application/json" -H "Authorization: Bearer $TOKEN"
}

# Wrapper function for AXA OpenPAAS API to get the status of a project creation request
# The status.out file (created by the ap_project_action function) is inspected to extract the
#   value of the os_project.status element.
# The value of os_project.status is then returned as the ID of the newly created project.
# If the project creation request fails, the return would either be null or an empty string.
function ap_get_project_status () {
local PROJECT_ID=$1
local TOKEN=$2
ap_project_action $PROJECT_ID $TOKEN GET
cat status.out | jq -r .os_project.status
rm status.out
}

# Wrapper function for AXA OpenPAAS API to get the status of a project deletion request
# The status.out file (created by the ap_project_action function) is inspected for a negative
# response to the get project's status request.
# Returns 0 if the correct response to a successful deletion is retrieved, else 1
function ap_get_project_delete_status () {
local PROJECT_ID=$1
local TOKEN=$2
ap_project_action $PROJECT_ID $TOKEN GET
cat status.out | grep "Accessed resource not found"
rm status.out
}



# Wrapper function for AXA OpenPAAS API to get the ID of a project given the name of a project
# If an ID can be found for the given project, the ID is also written to a file in the
#  metadata directory named as that of the project (ie same name as the project).
# Returns ID of the project if the ID can be found, else null
function ap_get_project_id (){
local PROJECT_NAME=$1
local SUBID=SUBSCRIPTION_ID_$2
local TOKEN=$3
if [ ! -f metadata/$PROJECT_NAME ];then
   curl -k -v -X GET -o project_id "$GATEWAY/?subscriptionId=$SUBID&name=$PROJECT_NAME&size=1" -H "Accept: application/json" -H "Authorization: Bearer $TOKEN"
   PROJECT_ID_HOLDER=`cat project_id | jq -r .projects[0].os_project.id`
   rm project_id
   if [[ ! -z $PROJECT_ID_HOLDER &&  $PROJECT_ID_HOLDER != "null" ]]; then
   echo $PROJECT_ID_HOLDER > metadata/$PROJECT_NAME
   fi
fi
echo `cat metadata/$PROJECT_NAME`
}

# ----------------------------------------------------
# Main

# setup tmp and logs directories
TMP_DIR=tmp
LOG_DIR=$LOGS_DIR
mkdir -p $TMP_DIR $LOG_DIR

# other directories
TEMPLATES_DIR=templates
PV_DIR=${TEMPLATES_DIR}/pv
CONFIG_MAP_DIR=${TEMPLATES_DIR}/configmap
PROJCONFIG_MAP_DIR=${TEMPLATES_DIR}/projconfigmap
SECRETS_DIR=${TEMPLATES_DIR}/secret

BASENAME=${0##*/}

set -x -e

if [[ "$BASENAME" == "build.sh" ]]; then
	logfile=$LOG_DIR/$BASENAME-$1.log
else
	logfile=$LOG_DIR/$BASENAME-$1-$2.log
fi

exec > >(tee -i $logfile)
exec 2>&1

trap cleanup EXIT
