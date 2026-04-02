#!/usr/bin/env bash
set -euo pipefail

# =============================================
# One-time setup: Custom Domain + HTTPS
# S3 + CloudFront + Route 53 + ACM
# =============================================
# Edit these variables:

BUCKET_NAME="devinsmellsofdogfartsandsoup"
DOMAIN_NAME="devinsmellsofdogfartsandsoup.com"
REGION="us-east-1"  # ACM certs for CloudFront MUST be in us-east-1

# =============================================

echo "=== Setting Up Devin's Domain of Shame ==="

# --- Step 1: Request ACM certificate (must be us-east-1 for CloudFront) ---
echo ""
echo "Step 1: Requesting ACM certificate for $DOMAIN_NAME..."
CERT_ARN=$(aws acm request-certificate \
    --domain-name "$DOMAIN_NAME" \
    --validation-method DNS \
    --region "$REGION" \
    --query 'CertificateArn' \
    --output text)
echo "  Certificate ARN: $CERT_ARN"
echo "  Status: PENDING_VALIDATION"

# --- Step 2: Create Route 53 hosted zone ---
echo ""
echo "Step 2: Creating Route 53 hosted zone for $DOMAIN_NAME..."
CALLER_REF="setup-$(date +%s)"
ZONE_RESULT=$(aws route53 create-hosted-zone \
    --name "$DOMAIN_NAME" \
    --caller-reference "$CALLER_REF" \
    --output json 2>/dev/null || true)

if [ -n "$ZONE_RESULT" ]; then
    HOSTED_ZONE_ID=$(echo "$ZONE_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['HostedZone']['Id'].split('/')[-1])")
    echo "  Hosted Zone ID: $HOSTED_ZONE_ID"
else
    echo "  Hosted zone may already exist. Looking it up..."
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name \
        --dns-name "$DOMAIN_NAME" \
        --query "HostedZones[?Name=='${DOMAIN_NAME}.'].Id" \
        --output text | head -1 | sed 's|/hostedzone/||')
    echo "  Hosted Zone ID: $HOSTED_ZONE_ID"
fi

# --- Step 3: Get DNS validation records from ACM ---
echo ""
echo "Step 3: Retrieving DNS validation records..."
echo "  Waiting a moment for ACM to generate validation records..."
sleep 5

VALIDATION_JSON=$(aws acm describe-certificate \
    --certificate-arn "$CERT_ARN" \
    --region "$REGION" \
    --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
    --output json)

VALIDATION_NAME=$(echo "$VALIDATION_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['Name'])")
VALIDATION_VALUE=$(echo "$VALIDATION_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['Value'])")

echo "  Validation CNAME: $VALIDATION_NAME -> $VALIDATION_VALUE"

# --- Step 4: Add validation CNAME to Route 53 ---
echo ""
echo "Step 4: Adding DNS validation record to Route 53..."
CHANGE_BATCH=$(cat <<EOF
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$VALIDATION_NAME",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "$VALIDATION_VALUE"}]
    }
  }]
}
EOF
)

aws route53 change-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch "$CHANGE_BATCH" \
    --output text
echo "  Validation record added. Certificate will validate automatically (may take a few minutes)."

# --- Step 5: Create CloudFront Origin Access Identity ---
echo ""
echo "Step 5: Creating CloudFront Origin Access Identity..."
OAI_RESULT=$(aws cloudfront create-cloud-front-origin-access-identity \
    --cloud-front-origin-access-identity-config \
    "CallerReference=devin-oai-$(date +%s),Comment=OAI for $BUCKET_NAME" \
    --output json)

OAI_ID=$(echo "$OAI_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['CloudFrontOriginAccessIdentity']['Id'])")
OAI_CANONICAL=$(echo "$OAI_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['CloudFrontOriginAccessIdentity']['S3CanonicalUserId'])")
echo "  OAI ID: $OAI_ID"

# --- Step 6: Set S3 bucket policy for OAI ---
echo ""
echo "Step 6: Setting S3 bucket policy for CloudFront OAI access..."
BUCKET_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "CloudFrontOAIAccess",
    "Effect": "Allow",
    "Principal": {"CanonicalUser": "$OAI_CANONICAL"},
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
  }]
}
EOF
)

aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy "$BUCKET_POLICY"
echo "  Bucket policy applied."

# --- Step 7: Create CloudFront distribution ---
echo ""
echo "Step 7: Creating CloudFront distribution..."
DIST_CONFIG=$(cat <<EOF
{
  "CallerReference": "devin-dist-$(date +%s)",
  "Comment": "Devin Smells Of Dog Farts and Soup",
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-$BUCKET_NAME",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]},
    "CachedMethods": {"Quantity": 2, "Items": ["GET", "HEAD"]},
    "ForwardedValues": {"QueryString": false, "Cookies": {"Forward": "none"}},
    "MinTTL": 0,
    "DefaultTTL": 86400,
    "MaxTTL": 31536000,
    "Compress": true
  },
  "Origins": {
    "Quantity": 1,
    "Items": [{
      "Id": "S3-$BUCKET_NAME",
      "DomainName": "$BUCKET_NAME.s3.amazonaws.com",
      "S3OriginConfig": {
        "OriginAccessIdentity": "origin-access-identity/cloudfront/$OAI_ID"
      }
    }]
  },
  "DefaultRootObject": "index.html",
  "Enabled": true,
  "Aliases": {"Quantity": 1, "Items": ["$DOMAIN_NAME"]},
  "ViewerCertificate": {
    "ACMCertificateArn": "$CERT_ARN",
    "SSLSupportMethod": "sni-only",
    "MinimumProtocolVersion": "TLSv1.2_2021"
  },
  "PriceClass": "PriceClass_100",
  "HttpVersion": "http2and3"
}
EOF
)

DIST_RESULT=$(aws cloudfront create-distribution \
    --distribution-config "$DIST_CONFIG" \
    --output json)

DIST_ID=$(echo "$DIST_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Distribution']['Id'])")
DIST_DOMAIN=$(echo "$DIST_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Distribution']['DomainName'])")

echo "  Distribution ID: $DIST_ID"
echo "  CloudFront Domain: $DIST_DOMAIN"

# --- Step 8: Add Route 53 alias record ---
echo ""
echo "Step 8: Adding Route 53 alias record: $DOMAIN_NAME -> $DIST_DOMAIN..."
ALIAS_BATCH=$(cat <<EOF
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$DOMAIN_NAME",
      "Type": "A",
      "AliasTarget": {
        "HostedZoneId": "Z2FDTNDATAQYW2",
        "DNSName": "$DIST_DOMAIN",
        "EvaluateTargetHealth": false
      }
    }
  }]
}
EOF
)

aws route53 change-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch "$ALIAS_BATCH" \
    --output text
echo "  DNS alias created."

# --- Summary ---
echo ""
echo "============================================"
echo "  SETUP COMPLETE"
echo "============================================"
echo ""
echo "  Domain:          $DOMAIN_NAME"
echo "  CloudFront:      $DIST_DOMAIN"
echo "  Distribution ID: $DIST_ID"
echo "  Certificate:     $CERT_ARN"
echo "  Hosted Zone:     $HOSTED_ZONE_ID"
echo ""
echo "  IMPORTANT: Update deploy.sh with:"
echo "    DISTRIBUTION_ID=\"$DIST_ID\""
echo ""
echo "  IMPORTANT: Update your domain registrar's"
echo "  nameservers to point to the Route 53 hosted zone."
echo "  Run this to see the nameservers:"
echo ""
echo "    aws route53 get-hosted-zone --id $HOSTED_ZONE_ID \\"
echo "      --query 'DelegationSet.NameServers' --output table"
echo ""
echo "  DNS propagation may take up to 48 hours."
echo "  Certificate validation usually completes in ~5 minutes"
echo "  once DNS is properly configured."
echo "============================================"
