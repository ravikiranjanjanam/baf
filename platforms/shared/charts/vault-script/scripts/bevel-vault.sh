#!/bin/bash

##############################################################################################################################
################################################## Utility functions starts ##################################################
##############################################################################################################################

# This function validates hashicorp vault responses 
function validateVaultResponseHashicorp {
    if echo ${2} | grep "errors" || [[ "${2}" = "" ]]; then
        echo "ERROR: unable to retrieve ${1}: ${2}"
        exit 1
    fi
    if  [[ "$3" = "LOOKUPSECRETRESPONSE" ]]
    then
        http_code=$(curl -fsS -o /dev/null -w "%{http_code}" \
        --header "X-Vault-Token: ${VAULT_TOKEN}" \
        ${VAULT_ADDR}/v1/${1})
        curl_response=$?
        if test "$http_code" != "200" ; then
            echo "Http response code from Vault - $http_code and curl_response - $curl_response"
            if test "$curl_response" != "0"; then
                echo "Error: curl command failed with error code - $curl_response"
                exit 1
            fi
        fi
    fi
}

##############################################################################################################################
################################################## Hashicorp vault functions Starts ##########################################
##############################################################################################################################

function initHashicorpVaultToken {
    KUBE_SA_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    VAULT_TOKEN=$(curl -sS --request POST ${VAULT_ADDR}/v1/auth/${KUBERNETES_AUTH_PATH}/login -H "Content-Type: application/json" -d \
                '{"role":"'"${VAULT_APP_ROLE}"'","jwt":"'"${KUBE_SA_TOKEN}"'"}' | jq -r 'if .errors then . else .auth.client_token end')
}

#Arg1: Vault token; Arg2: Secret Path
function readHashicorpVaultSecret {
    # Hashicorp v2 secret data path format
    #secret_path=$VAULT_SECRET_PATH/data/$1
    # Curl to the vault server
    VAULT_SECRET=$(curl --header "X-Vault-Token: ${VAULT_TOKEN}" ${VAULT_ADDR}/v1/${1} | jq -r 'if .errors then "null" else .data end')
}

function writeHashicorpVaultSecret {
    #secret_path=$VAULT_SECRET_PATH/data/$1
    VAULT_RESPONSE=$(curl \
                  -H "X-Vault-Token: ${VAULT_TOKEN}" \
                  -H "Content-Type: application/json" \
                  -X POST \
                  -d @${2} \
                  ${VAULT_ADDR}/v1/${1})
}

##############################################################################################################################
################################################## AWS Secret Manager functions starts #######################################
##############################################################################################################################

function initAWSSecretManager {
    aws configure set aws_access_key_id $CLIENT_ID
    aws configure set aws_secret_access_key $CLIENT_SECRET
    aws configure set default.region "eu-west-1"
}

function readAWSSecretManager {
    RESP=$(aws secretsmanager get-secret-value --secret-id $VAULT_SECRET_PATH/${1} | jq -r ".SecretString")
    if [[ "$RESP" == "" ]]
    then
        VAULT_SECRET="null"
    else
        VAULT_SECRET=$(echo ${RESP} | sed -e 's!\\n !\\n!g') # Remove the extra space in the new lines of certificate
    fi
}

#Arg1: Secret keyname
#Arg2: Secret value
function writeAWSSecretManger {
    # Format data as per required by AKV
    VAULT_RESPONSE=$(aws secretsmanager create-secret --name $VAULT_SECRET_PATH/${1} --secret-string file://${2})
}

##############################################################################################################################
################################################## AZURE key vault functions starts ##########################################
##############################################################################################################################

function initAzureVaultToken {
    VAULT_TOKEN=$(curl --location --request POST https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token \
                                --form 'grant_type="client_credentials"' \
                                --form 'client_id="'${CLIENT_ID}'"' \
                                --form 'client_secret="'${CLIENT_SECRET}'"' \
                                --form 'scope="https://vault.azure.net/.default"' | jq '.access_token' | sed -e 's/^"//' -e 's/"$//') # sed to remove the quotes at from start and end
}

#Arg1: Secret keyname
function readAzureVaultSecret {
    VAULT_SECRET=$(curl --location --request GET ${VAULT_ADDR}/secrets/${1}?api-version=7.3 \
                                    --header 'Authorization: Bearer '${VAULT_TOKEN} | jq '.value' | sed -e 's/^"//' -e 's/"$//') # sed to remove the quotes at from start and end
}

#Arg1: Secret keyname
#Arg2: Secret value
function writeAzureVaultSecret {
    # Format data as per required by AKV
    JSON_PAYLOAD=$(cat ${2} | sed -e 's!"!\\"!g')
    VAULT_RESPONSE=$(curl --location --request PUT ${VAULT_ADDR}/secrets/${1}?api-version=7.3 \
                                    --header 'Authorization: Bearer '${VAULT_TOKEN} --header 'Content-Type: application/json' \
                                    --data-raw '{"value": "'"$JSON_PAYLOAD"'"}' )
}


##############################################################################################################################
################################################## Vault main handler function ###############################################
##############################################################################################################################

vaultBevelFunc() {
    if [[ $VAULT_TYPE = "hashicorp" ]]; then
        if [[ $1 = "init" ]] 
        then
            initHashicorpVaultToken
            echo $VAULT_TOKEN 
        fi
        if [[ $1 = "readJson" ]] 
        then
            readHashicorpVaultSecret "$2"
            echo $VAULT_SECRET
        fi
        if [[ $1 = "write" ]] 
        then
            writeHashicorpVaultSecret "$2" "$3"
            echo $VAULT_RESPONSE
        fi
    fi
    if [[ $VAULT_TYPE = "aws" ]]; then
        if [[ $1 = "init" ]] 
        then
            initAWSSecretManager
        fi
        if [[ $1 = "readJson" ]] 
        then
            if [[ $2 = "" ]]
            then
                exit 1
            else
                readAWSSecretManager "$2"
                echo $VAULT_SECRET
            fi
        fi
        if [[ $1 = "write" ]] 
        then
            writeAWSSecretManger "$2" "$3"
            echo $VAULT_RESPONSE
        fi
    fi
    if [[ $VAULT_TYPE = "azure" ]]; then
        if [[ $1 = "init" ]] 
        then
            initAzureVaultToken
            echo $VAULT_TOKEN
        fi
        if [[ $1 = "readJson" ]] 
        then
            if [[ $2 = "" ]]
            then
                exit 1
            else
                readAzureVaultSecret $(echo $2 | sed -e 's!/!-!g' | sed -e 's!\.!-!g') # sed to change the / and . to -  in the vault path as akv doesn't support / in secret names
                echo $(echo $VAULT_SECRET | sed -e 's!\\n\\n!\\n!g') | sed -e 's!\\"!"!g'
            fi
        fi
        if [[ $1 = "write" ]] 
        then
            echo $3
            writeAzureVaultSecret $(echo $2 | sed -e 's!/!-!g' | sed -e 's!\.!-!g') "$3"
            echo $VAULT_RESPONSE
        fi
    fi
}