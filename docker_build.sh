#!/bin/bash
#docker build . -t 'mchristopher/canvas-lms-docker:latest'
docker buildx build --platform linux/amd64,linux/arm64 -t mchristopher/canvas-lms-docker:latest .

docker buildx build --platform linux/amd64,linux/arm64 -t mchristopher/canvas-lms-docker:latest-core --push -f Dockerfile.core . 
#docker build -t mchristopher/canvas-lms-docker:latest-core -f Dockerfile.core . 
docker buildx build --platform linux/amd64,linux/arm64 -t mchristopher/canvas-lms-docker:latest --push -f Dockerfile.app . 
