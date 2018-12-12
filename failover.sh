#!/bin/sh
#
# Copyright 2018 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
# http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.
#

# Bailout on error
set -e

function usage() {
  cat << EOF

Usage: 
`basename ${0}` -f <terraform state file>
`basename ${0}` -c <cf distribution id> -u <website url> -i <origin identity> -f <failover bucket fqdn>
EOF
}


which aws > /dev/null
if [[ $? -gt 0 ]] ; then 
  echo "AWS CLI not found - please go to https://aws.amazon.com/cli/ for more information on how to install it"
fi

which jq > /dev/null
if [[ $? -gt 0 ]] ; then 
  echo "JQ not found - please go to https://stedolan.github.io/jq/download/ for more information on how to install it"
fi

PARAMS=""
while (( "$#" )); do
  case "$1" in
    -s|--terraform-state-file)
      TFARG=$2
      shift 2
      ;;
    -c|--cloudfront-distribution-id)
      CFIDARG=$2
      shift 2
      ;;
    -u|--cloudfront-distribution-url)
      CFURLARG=$2
      shift 2
      ;;
    -i|--failover-origin-identity)
      FIDARG=$2
      shift 2
      ;;
    -f|--failover-bucket-fqdn)
      FQDNARG=$2
      shift 2
      ;;      
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      usage
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done

# Dynamically extract variables from terraform state file.
if [[ $TFARG && (-f ${TFARG}) ]] ; then
  echo "Found terraform state file.. Extracting parameters."
	CLOUDFRONT_ID=$( jq -r '.modules[0].resources["aws_cloudfront_distribution.website_cdn"].primary.id' ${TFARG} )
	CLOUDFRONT_URL="https://$( jq -r '.modules[0].resources["aws_cloudfront_distribution.website_cdn"].primary.attributes.domain_name' ${TFARG} )/"
	FAILOVER_IDENTITY=$( jq -r '.modules[0].resources["aws_cloudfront_origin_access_identity.origin_failover_access_identity"].primary.id' ${TFARG} )
	FAILOVER_BUCKET_FQDN=$( jq -r '.modules[0].resources["aws_s3_bucket.failover_bucket"].primary.attributes.bucket_regional_domain_name' ${TFARG} )
elif [[ $CFIDARG && $CFURLARG && $FIDARG && $FQDNARG ]] ; then
  CLOUDFRONT_ID=$CFIDARG
  CLOUDFRONT_URL=$CFURLARG
  FAILOVER_IDENTITY=$FIDARG
  FAILOVER_BUCKET_FQDN=$FQDNARG
else
  usage
  exit 1
fi

# Explicitly declared variables
#CLOUDFRONT_ID="E1M6O00B4Y4FZB"
#FAILOVER_IDENTITY="E3OWF7EI8B3BBU"
#FAILOVER_BUCKET_FQDN="failover-website20181206082214035700000002.s3.ap-southeast-2.amazonaws.com"
#CLOUDFRONT_URL="https://d1593sj4rzbbcp.cloudfront.net/"

# Get MD5 of current root objecvt. We eill use this to validate that the chganges have taken effect later
ORIGINAL_MD5=$(curl -s "${CLOUDFRONT_URL}" | md5)
echo "Current distribution root object MD5 is ${ORIGINAL_MD5}."

if [ ! -d ./tmp ] ; then
  mkdir ./tmp/
fi

# Prepare our override template with failover variables.
jq -r --arg ID "${FAILOVER_IDENTITY}" --arg FQDN "${FAILOVER_BUCKET_FQDN}" '.Origins.Items[0].DomainName=$FQDN | .Origins.Items[0].S3OriginConfig.OriginAccessIdentity="origin-access-identity/cloudfront/"+$ID' override_template.json > tmp/failover_config.json

# Get current cloudfront distribution configuration.
echo "Getting existing distribution configuration."
aws cloudfront get-distribution-config --id ${CLOUDFRONT_ID} > tmp/original_config.json
echo "Original configuration stored at tmp/original_config.json"

# Extract ETAG value from current config. This is needed later during the update process.
ETAG=$(cat tmp/original_config.json | jq -r ".ETag")

echo "Merging failover configuration."
# Scope down the distribution configuration.
jq -r '.DistributionConfig' tmp/original_config.json > tmp/filtered_config.json
# Merge new updates on top of old file.
jq -r --argfile failover tmp/failover_config.json '. + $failover' tmp/filtered_config.json  > tmp/updated_config.json

# Apply updated config file
echo "Updating CloudFront distribution...\c"
RESULT=$(aws cloudfront update-distribution --id ${CLOUDFRONT_ID} --if-match ${ETAG} --distribution-config file://tmp/updated_config.json)
echo "Done."

# Invalidate entire distribution
INVALIDATION=$(aws cloudfront create-invalidation --distribution-id ${CLOUDFRONT_ID} --paths "/*")

echo "Invalidating CloudFront cache... please be patient! Maybe get some tea or coffee."
aws cloudfront wait invalidation-completed  --distribution-id ${CLOUDFRONT_ID} --id=$(echo ${INVALIDATION} | jq -r '.Invalidation.Id')

echo "Cache invalidated."

echo "Checking distribution update.\c"

WAIT_TIMEOUT=60
WAIT_COUNT=0

while [ "$(curl -s ${CLOUDFRONT_URL} | md5)" == "${ORIGINAL_MD5}" ] ; do
	if [ $WAIT_COUNT -eq $WAIT_TIMEOUT ] ; then 
		echo "" ; echo "${WAIT_COUNT} second timeout reached. Exiting"
		exit 1 ; break
	fi
	((WAIT_COUNT++))
	echo ".\c"
	sleep 1
done
echo "CloudFront distribution updated....Distribution root object MD5 is now $(curl -s ${CLOUDFRONT_URL} | md5)."





