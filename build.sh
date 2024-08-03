#!/bin/bash
# Build, tag and push docker image to dockerhub.
# usage build.sh <docker repo name> <docker tag> push latest
# push and latest are both optional, and the order of arguments passed in must be in the correct order
# example:- build.sh username/my-project 1.4.12_rc1 push latest
#           will create the image username/my-project:1.4.12_rc1 and username/my-project:latest and push both to docker hub

NAME=$1
TAG=$2
PUSH=$3
LATEST=$4
WORKING_DIR="$(dirname "$(realpath "$0")")"

# Function to log to Docker logs
log() {
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${GREEN}${TIMESTAMP}${NC} - $@"
}

# Function to log errors to Docker logs with timestamp
log_error() {
    local TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    while read -r line; do
        echo -e "${YELLOW}${TIMESTAMP}${NC} - ERROR - $line"
    done
}

build() {
    local name=$1
    local tag=$2

    build_cmd="${name}:${tag}"
    log "Building: ${build_cmd}..."
    docker build -t "$build_cmd" $WORKING_DIR
    log "Done."
}

tag() {
    local name=$1
    local tag=$2

    tag_from="${name}:${tag}"
    tag_to="${name}:latest"
    if [ -n "$LATEST" ]; then
        log "Adding '"'latest'"' tag to ${tag_from}"
        docker tag "$tag_from" "$tag_to"
    fi
}

push() {
    local name=$1
    local tag=$2
    log "Pushing ${name}:${tag}..."
    docker push "${name}:${tag}"
    log "Done."
    if [ -n "$LATEST" ]; then
        log "Pushing ${name}:latest..."
        docker push "${name}:latest"
        log "Done."
    fi
}

case $PUSH in
    push)
      build $NAME $TAG
      tag $NAME $TAG
      push $NAME $TAG
    ;;
    *)
      build $NAME $TAG
      tag $NAME $TAG
    ;;
esac
