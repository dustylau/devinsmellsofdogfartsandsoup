#!/usr/bin/env bash
set -euo pipefail

# =============================================
# Deploy Devin Smells to S3 + CloudFront
# =============================================
# Edit these variables before first use:

BUCKET_NAME="devinsmellsofdogfartsandsoup"
REGION="us-east-1"
DISTRIBUTION_ID=""  # Fill in after creating CloudFront distribution

# =============================================

INDEX_FILE="index.html"

if [ ! -f "$INDEX_FILE" ]; then
    echo "ERROR: $INDEX_FILE not found. Run 'python build.py' first."
    exit 1
fi

echo "=== Deploying Devin's Shame ==="

# --- Step 1: Create S3 bucket (idempotent) ---
echo "Ensuring S3 bucket exists: $BUCKET_NAME"
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$REGION"
    else
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$REGION" \
            --create-bucket-configuration "LocationConstraint=$REGION"
    fi
    echo "  Created bucket: $BUCKET_NAME"
else
    echo "  Bucket already exists."
fi

# --- Step 2: Choose website-only or CloudFront-backed deployment ---
if [ -n "$DISTRIBUTION_ID" ]; then
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    echo "  Public access blocked (CloudFront serves content)."
else
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

    aws s3api put-bucket-website \
        --bucket "$BUCKET_NAME" \
        --website-configuration '{"IndexDocument":{"Suffix":"index.html"}}'

    BUCKET_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadIndex",
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
  }]
}
EOF
)

    aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy "$BUCKET_POLICY"
    echo "  Static website hosting enabled for direct S3 access."
fi

# --- Step 3: Upload index.html ---
echo "Uploading $INDEX_FILE..."
aws s3 cp "$INDEX_FILE" "s3://$BUCKET_NAME/$INDEX_FILE" \
    --content-type "text/html; charset=utf-8" \
    --cache-control "public, max-age=3600, s-maxage=86400"
echo "  Uploaded."

# --- Step 4: Invalidate CloudFront cache ---
if [ -n "$DISTRIBUTION_ID" ]; then
    echo "Invalidating CloudFront cache..."
    aws cloudfront create-invalidation \
        --distribution-id "$DISTRIBUTION_ID" \
        --paths "/*" \
        --output text
    echo "  Cache invalidation submitted."
else
    echo "DISTRIBUTION_ID not set — skipping CloudFront invalidation."
    echo "  Set DISTRIBUTION_ID in this script after creating the distribution."
fi

echo ""
echo "=== Deploy complete ==="
if [ -n "$DISTRIBUTION_ID" ]; then
    echo "Site will be available at your CloudFront domain shortly."
else
    echo "Website URL: http://$BUCKET_NAME.s3-website-$REGION.amazonaws.com"
    echo "Optional next step: create CloudFront and set DISTRIBUTION_ID in this script."
fi
