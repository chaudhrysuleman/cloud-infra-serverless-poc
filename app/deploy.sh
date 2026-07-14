#!/bin/bash
set -e

# Parse arguments to select IaC provider (default: terraform)
USE_PULUMI=false
if [ "$1" == "--pulumi" ]; then
    USE_PULUMI=true
fi

echo "Step 1: Building Spring Boot application locally..."
mvn clean package -DskipTests

if [ "$USE_PULUMI" = true ]; then
    echo "🌐 Step 2: Running Pulumi Up to provision cloud infrastructure and deploy Lambda..."
    cd ../pulumi
    export PULUMI_CONFIG_PASSPHRASE="SecurePass123!"
    ~/.pulumi/bin/pulumi up --yes
    
    echo "🔍 Extracting Pulumi outputs..."
    API_URL=$(~/.pulumi/bin/pulumi stack output api_gateway_url)
    cd ../app
else
    echo "🌐 Step 2: Running Terraform Apply to provision cloud infrastructure and deploy Lambda..."
    cd ../terraform
    terraform apply -auto-approve
    
    echo "🔍 Extracting Terraform outputs..."
    API_URL=$(terraform output -raw api_gateway_url)
    cd ../app
fi

echo "🎉 Deployment completed successfully!"
echo "🔗 Access via API Gateway URL: $API_URL"
echo "Check the health: $API_URL/api/orders/healthcheck"
