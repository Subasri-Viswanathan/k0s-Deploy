#!/usr/bin/env bash
# Copyright (c) Syncfusion Inc. All rights reserved.

set -e

# Variable declaration.
repo_url="https://github.com/ranganathan-arumugam/k0s-Deploy/raw/main/private-cloud.zip"
destination="/manifest"

# Parse command-line arguments
for arg in "$@"; do
  case $arg in
    --storage-account-name=*)
      storage_account_name="${arg#*=}"
      ;;
    --storage-account-key=*)
      storage_account_key="${arg#*=}"
      ;;
    --fileshare-name=*)
      fileshare_name="${arg#*=}"
      ;;
    --app_base_url=*)
      app_base_url="${arg#*=}"
      ;;
  esac
done

# Function to display colored output
function say {
  color=$1
  message=$2
  echo "Info: $(tput setaf $color)$message$(tput sgr0)"
}

# Function to display error message and exit
function handle_error {
  say 1 "Error: $1"
  exit 1
}

# Function to check if a command is available
function command_exists {
  command -v "$1" >/dev/null 2>&1
}

# Function to install required packages
function install_packages {
  for package in "$@"; do
    if ! command_exists "$package"; then
      say 4 "Installing $package..."
      sudo apt-get update
      sudo apt-get install -y "$package"
      say 2 "$package installed successfully."
    else
      say 2 "$package is already installed."
    fi
  done
}

# Function to download and unzip GitHub repository
function download_and_unzip_manifest {
  [ -d "$destination" ] && rm -r "$destination"
  mkdir -p "$destination"
  say 4 "Downloading and extracting GitHub repository..."
  curl -sSL "$repo_url" -o repo.zip
  unzip -qq repo.zip -d "$destination"
  rm repo.zip
}

# Function to update fileshare name in configuration
function update_fileshare_name {
  pvconfig_file="$destination/private-cloud/boldreports/configuration/pvclaim_azure_smb.yaml"
  if [ -f "$pvconfig_file" ]; then
    sed -i -e "s/^ *shareName: <fileshare>/   shareName: $fileshare_name/" "$pvconfig_file"
  else
    handle_error "Pvclaim file is not available"
  fi

  kustomfile="$destination/private-cloud/kustomization.yaml"
  #sed -i -e "s/^ *#- boldreports/configuration/pvclaim_azure_smb.yaml/  - boldreports/configuration/pvclaim_azure_smb.yaml/" "$kustomfile"
  sed -i -e "s/^ *#- boldreports\/configuration\/pvclaim_azure_smb\.yaml/  - boldreports\/configuration\/pvclaim_azure_smb.yaml/" "$kustomfile"

  #sed -i -e "s/^ *- boldreports/configuration/pvclaim_onpremise.yaml/   #- boldreports/configuration/pvclaim_onpremise.yaml/" "$kustomfile"
  sed -i -e "s/^ *- boldreports\/configuration\/pvclaim_onpremise\.yaml/  #- boldreports\/configuration\/pvclaim_onpremise.yaml/" "$kustomfile"  
}

# Function to update app_base_url in deployment file
function app_base_url_mapping {
  deploy_file="$destination/private-cloud/boldreports/deployment.yaml"
  sed -i -e "s|^ *value: <application_base_url>|          value: $app_base_url|" "$deploy_file"
}

# Function to configure NGINX
function nginx_configuration {
  cluster_ip=$(k0s kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.clusterIP}')
  domain=$(echo "$app_base_url" | sed 's~^https\?://~~')
  nginx_conf="/etc/nginx/sites-available/default"
  cp /manifest/private-cloud/boldreports/certificate.pem /etc/nginx/sites-available
  cp /manifest/private-cloud/boldreports/private-key.pem /etc/nginx/sites-available
  
  # Remove existing nginx configuration file
  [ -e "$nginx_conf" ] && rm "$nginx_conf"
  
  if [ -n "$app_base_url" ]; then
    nginx_conf_content="
    server {
      listen 80;
      server_name $domain;
      return 301 https://$domain$request_uri;
    }

    server {
      server_name $domain;
      listen 443 ssl;
      ssl_certificate /etc/nginx/sites-available/certificate.pem;
      ssl_certificate_key /etc/nginx/sites-available/private-key.pem;

      location / {
        proxy_pass http://$cluster_ip;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
        proxy_set_header X-Forwarded-Host \$host;
      }
    }"
  else
    nginx_conf_content="
    server {
      listen 80 default_server;
      listen [::]:80 default_server;

      location / {
        proxy_pass http://$cluster_ip;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
        proxy_set_header X-Forwarded-Host \$host;
      }
    }"
  fi

  echo "$nginx_conf_content" | sudo tee "$nginx_conf"
  sudo chmod +x "$nginx_conf"
  nginx -t
  nginx -s reload
}

function show_bold_reports_graphic {
  echo ""
  echo "██████╗  ██████╗ ██╗     ██████╗     ██████╗ ███████╗██████╗  ██████╗ ██████╗ ████████╗███████╗"
  echo "██╔══██╗██╔═══██╗██║     ██╔══██╗    ██╔══██╗██╔════╝██╔══██╗██╔═══██╗██╔══██╗╚══██╔══╝██╔════╝"
  echo "██████╔╝██║   ██║██║     ██║  ██║    ██████╔╝█████╗  ██████╔╝██║   ██║██████╔╝   ██║   ███████╗"
  echo "██╔══██╗██║   ██║██║     ██║  ██║    ██╔══██╗██╔══╝  ██╔═══╝ ██║   ██║██╔══██╗   ██║   ╚════██║"
  echo "██████╔╝╚██████╔╝███████╗██████╔╝    ██║  ██║███████╗██║     ╚██████╔╝██║  ██║   ██║   ███████║"
  echo "╚═════╝  ╚═════╝ ╚══════╝╚═════╝     ╚═╝  ╚═╝╚══════╝╚═╝      ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝"
  echo ""
}

# Function to install k0s
function install_k0s {
  say 4 "Installing k0s..."
  command_exists k0s && say 2 "k0s is already installed." || { curl -sSLf https://get.k0s.sh | sudo sh; }
}

# Function to start k0s cluster
function start_k0s {
  k0s kubectl get nodes &> /dev/null || {
    say 4 "Starting k0s cluster..."
    sudo k0s install controller --single &
    sleep 5
    sudo k0s start &
    sleep 10
  }
}

function domain_mapping {
  # File path to your YAML configuration file
  config_file="/manifest/private-cloud/boldreports/ingress.yaml"

  # Domain to replace with
  new_domain=$(echo "$app_base_url" | sed 's~^https\?://~~')

  # Uncomment and replace domain in the specified lines
  sed -i -e 's/^ *# tls:/  tls:/' \
         -e 's/^ *# - hosts:/  - hosts:/' \
         -e "s/^ *# - example.com/    - $new_domain/" \
         -e 's/^ *# secretName: boldreports-tls/    secretName: boldreports-tls/' \
         -e "s/^ *- #host: example.com/  - host: $new_domain/" \
         "$config_file"

  say 4 "Domain mapped in the ingress file."
}

# Function to install Bold Reports
function install_bold_reports {
  install_packages nginx zip
  download_and_unzip_manifest
  install_k0s
  start_k0s
  echo $app_base_url
  say 4 "Checking app_base_url provided"
  if [ -n "$app_base_url" ]; then
    app_base_url_mapping
    domain_mapping
  else
      say 3 "Skipping app_base_url mapping as it is not provided"
  fi

  k0s kubectl get nodes &> /dev/null || handle_error "k0s cluster is not running."
  
  if [ -n "$storage_account_name" ] && [ -n "$storage_account_key" ] && [ -n "$fileshare_name" ]; then
    update_fileshare_name
    # Check if the secret already exists
    if k0s kubectl get secret bold-azure-secret > /dev/null 2>&1; then
      say 4 "Secret bold-azure-secret already exists. Skipping creation."
    else
      say 4 "Creating azure secret"
      k0s kubectl create secret generic bold-azure-secret --from-literal azurestorageaccountname="$storage_account_name" --from-literal azurestorageaccountkey="$storage_account_key" --type=Opaque
    fi
  else
    say 3 "Skipping fileshare mounting details as they are not provided."
  fi

  say 4 "Deploying Bold Reports application..."
  k0s kubectl apply -k "$destination/private-cloud"
  # if [ -n "$app_base_url" ]; then
  #   k0s kubectl create secret tls boldreports-tls -n bold-services --key "/manifest/private-cloud/boldreports/private-key.pem" --cert "/manifest/private-cloud/boldreports/certificate.pem"
  # fi

  nginx_configuration
  show_bold_reports_graphic

  say 2 "Bold Reports application deployed successfully!"
  say 4 "You can access 'boldreports' on $app_base_url after mapping your machine IP with "$(echo "$app_base_url" | sed 's~^https\?://~~')""
}

install_bold_reports
