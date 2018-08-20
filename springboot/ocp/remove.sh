#!/usr/bin/env bash

###################################################################
# Called from JIRA when a project removal is triggered
###################################################################

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR
source ./common.sh
source ./config

USAGE="\
Error: Wrong argument(s).
Usage: `basename $0` app-name_major_minor stage tokens ...
Example: hello-world_1_5 sit dUmMyT0k3NV4lU3 
'_' not allowed in app name!
"

if [ ! "$1" ]; then
        echo "$USAGE"
        exit 1
fi

APP=`echo $1 | cut -d_ -f1 | tr "[A-Z]" "[a-z]"`
BUILD_PROJ=$APP-build
RELTAG=`echo $1 | cut -d_ -f2-3`
RELTAG_URL=`echo $RELTAG | tr "_" "-"`

PROJTAG=`echo $RELTAG | cut -d_ -f1`
PROJTAG_URL=`echo $PROJTAG | tr "_" "-"`

STAGE=`echo $2 | tr "[A-Z]" "[a-z]"`
[ "$STAGE" = "sit" -o "$STAGE" = "uat" -o "$STAGE" = "stg" ] || exit 1

PROJ=${APP}-${STAGE}-${PROJTAG_URL}

shift
shift

TOKEN_BUILD_CLUSTER_CICD="$1"
TOKEN_BUILD_CLUSTER_ADMIN="$2"
TOKEN_DEPLOY_CLUSTER_CICD="$3"
TOKEN_DEPLOY_CLUSTER_ADMIN="$4"


echo -e "\n######################################################\n"
echo APP=$APP
echo PROJ=$PROJ
echo MYSTAGE=$MYSTAGE
echo RELTAG=$RELTAG
echo -e "\n######################################################\n"

set +x; echo -e "\n### Log in ##########\n"; set -x

set -e
OC_DEPLOY_CLI=$(oc_login $CLUSTER_DEPLOY build $TOKEN_DEPLOY_CLUSTER_CICD)
OC_DEPLOY_ADMIN_CLI=$(oc_login $CLUSTER_DEPLOY deploy $TOKEN_DEPLOY_CLUSTER_ADMIN)
set +e

set +x; echo -e "\n### Delete project $PROJ ##########\n"; set -x

$OC_DEPLOY_CLI delete project $PROJ 

## Delete PVs
if [ -d ${PV_DIR}/${STAGE} ]; then
        for pv in $(cd ${PV_DIR}/${STAGE}; ls *.yaml *.yml ); do
                pv_name=`echo $pv | cut -d. -f1`

                set +x; echo -e "\n### Deleting pv $pv_name for $PROJ ##########\n"; set -x
                ################# Check if PV is still bound #######################################
                # A persistent volume can only be deleted if it is not still bound to a project.   #
                # As a race may occur between the completion of the deletion of a project (the oc  #
                # command "$OC_DEPLOY_CLI delete project $PROJ" above) and the command to delete   #
                # the persistent volume below (the oc command "$OC_DEPLOY_ADMIN_CLI delete pv...") #
                # the check below is made to wait till the persistent volume is not bound before   #
                # the command to delete the persistent volume is issued.                           #
                # The check will run for 5 times, waiting 30 seconds each time.                    #
                RETRY=5
                while [ $($OC_DEPLOY_ADMIN_CLI get pv $pv_name-${APP}-${STAGE}-${RELTAG_URL} -o jsonpath="{.status.phase}") = "Bound" ]
                do
                  echo "Can't delete PV $pv_name-${APP}-${STAGE}-${RELTAG} yet. Still bound. Sleep for 30s."
                  sleep 30
                  let "RETRY = RETRY - 1"
                  if [ 0 -eq ${RETRY} ]
                  then
                    echo "Retried ${RETRY} times, PV still bound"
                    break
                  fi
                done
                ############### End of check for bound PV #########################################
                if [ $($OC_DEPLOY_ADMIN_CLI get pv $pv_name-${APP}-${STAGE}-${RELTAG_URL} -o jsonpath="{.status.phase}") = "Released" ]; then
                  $OC_DEPLOY_ADMIN_CLI delete pv $pv_name-${APP}-${STAGE}-${RELTAG_URL}
                  echo "$pv_name-${APP}-${STAGE}-${RELTAG_URL} deletion succeeded."
                else
                  echo "$pv_name-${APP}-${STAGE}-${RELTAG_URL} deletion failed."
                fi
        done
fi

set +x; echo DONE $0

