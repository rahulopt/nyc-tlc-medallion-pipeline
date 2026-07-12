#!/bin/bash

#############################################################
# Utility Library
# Common reusable functions
#############################################################

#############################################################
# Colors
#############################################################

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
NC="\033[0m"

#############################################################
# Logging
#############################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

#############################################################
# Exit
#############################################################

exit_on_error() {
    log_error "$1"
    exit 1
}

#############################################################
# AWS CLI Validation
#############################################################

check_aws_cli() {

    if ! command -v aws >/dev/null 2>&1
    then
        exit_on_error "AWS CLI is not installed."
    fi

    log_success "AWS CLI Found"

}

#############################################################
# AWS Credentials Validation
#############################################################

check_aws_credentials() {

    if ! aws sts get-caller-identity >/dev/null 2>&1
    then
        exit_on_error "AWS credentials are invalid."
    fi

    log_success "AWS Credentials Verified"

}