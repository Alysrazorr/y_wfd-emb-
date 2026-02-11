#!/bin/bash

# Docker-based build script for EMB project
# This script builds all jdk_* projects using Docker containers
# and copies the results to the dist folder

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJ_DIR="$(dirname "$SCRIPT_DIR")"

# Parse arguments
JDK_VERSION="${1:-all}"
BUILD_TOOL="${2:-all}"

# Function to display usage
usage() {
    echo "Usage: $0 [JDK_VERSION] [BUILD_TOOL]"
    echo ""
    echo "Arguments:"
    echo "  JDK_VERSION  : 8, 11, 17, 21, or 'all' (default: all)"
    echo "  BUILD_TOOL   : maven, gradle, or 'all' (default: all)"
    echo ""
    echo "Examples:"
    echo "  $0               # Build all projects"
    echo "  $0 8 gradle      # Build only JDK 8 Gradle projects"
    echo "  $0 11 maven      # Build only JDK 11 Maven projects"
    echo "  $0 17 all        # Build all JDK 17 projects (Maven + Gradle)"
    echo "  $0 all maven     # Build all Maven projects"
    echo ""
    exit 1
}

# Validate JDK version
if [[ ! "$JDK_VERSION" =~ ^(8|11|17|21|all)$ ]]; then
    echo "ERROR: Invalid JDK version '$JDK_VERSION'"
    echo "Valid options: 8, 11, 17, 21, all"
    echo ""
    usage
fi

# Validate build tool
if [[ ! "$BUILD_TOOL" =~ ^(maven|gradle|all)$ ]]; then
    echo "ERROR: Invalid build tool '$BUILD_TOOL'"
    echo "Valid options: maven, gradle, all"
    echo ""
    usage
fi

echo "========================================"
echo "EMB Docker Build Script"
echo "========================================"
echo "Project directory: $PROJ_DIR"
echo "JDK Version: $JDK_VERSION"
echo "Build Tool: $BUILD_TOOL"
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed or not in PATH"
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "ERROR: Docker Compose is not installed"
    exit 1
fi

# Determine docker compose command
if docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

echo "Using: $DOCKER_COMPOSE"
echo ""

# Clean dist folder only if building all projects
if [ "$JDK_VERSION" == "all" ] && [ "$BUILD_TOOL" == "all" ]; then
    echo "========================================"
    echo "WARNING: Full build mode detected!"
    echo "========================================"
    echo "This will DELETE the entire dist/ folder and rebuild all projects."
    echo ""

    if [ -d "$PROJ_DIR/dist" ]; then
        echo "Current dist folder contents:"
        JAR_COUNT_BEFORE=$(find "$PROJ_DIR/dist" -name "*.jar" 2>/dev/null | wc -l)
        echo "  - $JAR_COUNT_BEFORE JAR files found"
        echo "  - Location: $PROJ_DIR/dist"
    else
        echo "Dist folder does not exist yet."
    fi

    echo ""
    read -p "Do you want to continue and DELETE dist folder? (y/N): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "Build cancelled by user."
        echo "Tip: Use './scripts/docker-dist.sh <JDK> <TOOL>' for incremental builds"
        echo "     Example: ./scripts/docker-dist.sh 8 gradle"
        exit 0
    fi

    echo ""
    echo "Cleaning dist folder (building all projects)..."
    if [ -d "$PROJ_DIR/dist" ]; then
        rm -rf "$PROJ_DIR/dist"
    fi
    mkdir -p "$PROJ_DIR/dist"
    echo "Dist folder cleaned"
else
    echo "Incremental build mode - preserving existing dist folder..."
    mkdir -p "$PROJ_DIR/dist"
    echo "Building into existing dist folder (will overwrite duplicates)"
fi
echo ""

# Check if .m2 directory exists
M2_DIR="${HOME}/.m2"
if [ ! -d "$M2_DIR" ]; then
    echo "WARNING: Maven repository not found at $M2_DIR"
    echo "Creating directory..."
    mkdir -p "$M2_DIR"
fi

# Check if .gradle directory exists
GRADLE_DIR="${HOME}/.gradle"
if [ ! -d "$GRADLE_DIR" ]; then
    echo "WARNING: Gradle cache not found at $GRADLE_DIR"
    echo "Creating directory..."
    mkdir -p "$GRADLE_DIR"
fi

cd "$PROJ_DIR"

# Function to check if we should build a specific combination
should_build() {
    local jdk=$1
    local tool=$2

    # Check JDK version
    if [ "$JDK_VERSION" != "all" ] && [ "$JDK_VERSION" != "$jdk" ]; then
        return 1
    fi

    # Check build tool
    if [ "$BUILD_TOOL" != "all" ] && [ "$BUILD_TOOL" != "$tool" ]; then
        return 1
    fi

    return 0
}

# Function to check if a service exists in jdk folders
service_exists() {
    local jdk=$1
    local tool=$2
    local dir="jdk_${jdk}_${tool}"

    if [ -d "$PROJ_DIR/$dir" ]; then
        return 0
    fi
    return 1
}

echo "========================================"
echo "Building Docker images and running builds..."
echo "========================================"
echo ""

BUILDS_RUN=0

# Build JDK 8 Maven
if should_build "8" "maven" && service_exists "8" "maven"; then
    echo "Step: Building Docker image for JDK 8..."
    $DOCKER_COMPOSE -f docker-compose.build.yml build build-jdk8-maven
    echo ""
    echo ">>> Building JDK 8 Maven projects..."
    $DOCKER_COMPOSE -f docker-compose.build.yml run --rm build-jdk8-maven
    BUILDS_RUN=$((BUILDS_RUN + 1))
    echo ""
fi

# Build JDK 8 Gradle
if should_build "8" "gradle" && service_exists "8" "gradle"; then
    echo "Step: Building Docker image for JDK 8..."
    $DOCKER_COMPOSE -f docker-compose.build.yml build build-jdk8-gradle
    echo ""
    echo ">>> Building JDK 8 Gradle projects..."
    $DOCKER_COMPOSE -f docker-compose.build.yml run --rm build-jdk8-gradle
    BUILDS_RUN=$((BUILDS_RUN + 1))
    echo ""
fi

# Build JDK 11 Maven
if should_build "11" "maven" && service_exists "11" "maven"; then
    echo "Step: Building Docker image for JDK 11..."
    $DOCKER_COMPOSE -f docker-compose.build.yml build build-jdk11-maven
    echo ""
    echo ">>> Building JDK 11 Maven projects..."
    $DOCKER_COMPOSE -f docker-compose.build.yml run --rm build-jdk11-maven
    BUILDS_RUN=$((BUILDS_RUN + 1))
    echo ""
fi

# Build JDK 11 Gradle
if should_build "11" "gradle" && service_exists "11" "gradle"; then
    echo "Step: Building Docker image for JDK 11..."
    $DOCKER_COMPOSE -f docker-compose.build.yml build build-jdk11-gradle
    echo ""
    echo ">>> Building JDK 11 Gradle projects..."
    $DOCKER_COMPOSE -f docker-compose.build.yml run --rm build-jdk11-gradle
    BUILDS_RUN=$((BUILDS_RUN + 1))
    echo ""
fi

# Build JDK 17 Maven
if should_build "17" "maven" && service_exists "17" "maven"; then
    echo "Step: Building Docker image for JDK 17..."
    $DOCKER_COMPOSE -f docker-compose.build.yml build build-jdk17-maven
    echo ""
    echo ">>> Building JDK 17 Maven projects..."
    $DOCKER_COMPOSE -f docker-compose.build.yml run --rm build-jdk17-maven
    BUILDS_RUN=$((BUILDS_RUN + 1))
    echo ""
fi

# Build JDK 17 Gradle
if should_build "17" "gradle" && service_exists "17" "gradle"; then
    echo "Step: Building Docker image for JDK 17..."
    $DOCKER_COMPOSE -f docker-compose.build.yml build build-jdk17-gradle
    echo ""
    echo ">>> Building JDK 17 Gradle projects..."
    $DOCKER_COMPOSE -f docker-compose.build.yml run --rm build-jdk17-gradle
    BUILDS_RUN=$((BUILDS_RUN + 1))
    echo ""
fi

# Build JDK 21 Maven
if should_build "21" "maven" && service_exists "21" "maven"; then
    echo "Step: Building Docker image for JDK 21..."
    $DOCKER_COMPOSE -f docker-compose.build.yml build build-jdk21-maven
    echo ""
    echo ">>> Building JDK 21 Maven projects..."
    $DOCKER_COMPOSE -f docker-compose.build.yml run --rm build-jdk21-maven
    BUILDS_RUN=$((BUILDS_RUN + 1))
    echo ""
fi

# Copy additional files if any build was run
if [ $BUILDS_RUN -gt 0 ]; then
    echo ">>> Copying additional files (evomaster-agent, jacoco)..."
    $DOCKER_COMPOSE -f docker-compose.build.yml run --rm copy-additional-files
    echo ""
fi

echo "========================================"
echo "Cleaning up Docker containers..."
echo "========================================"
$DOCKER_COMPOSE -f docker-compose.build.yml down

echo ""
echo "========================================"
echo "Build Summary"
echo "========================================"
echo "Builds executed: $BUILDS_RUN"
echo "Checking dist folder contents..."
echo ""

JAR_COUNT=$(find "$PROJ_DIR/dist" -name "*.jar" 2>/dev/null | wc -l)
echo "Total JAR files created: $JAR_COUNT"
echo ""

if [ $JAR_COUNT -gt 0 ]; then
    echo "Files in dist:"
    ls -lh "$PROJ_DIR/dist"
    echo ""
    echo "========================================"
    echo "SUCCESS - Builds completed!"
    echo "========================================"
    echo "Output location: $PROJ_DIR/dist"
    echo "JDK Version: $JDK_VERSION"
    echo "Build Tool: $BUILD_TOOL"
elif [ $BUILDS_RUN -eq 0 ]; then
    echo "========================================"
    echo "No matching builds found!"
    echo "========================================"
    echo "JDK Version: $JDK_VERSION"
    echo "Build Tool: $BUILD_TOOL"
    echo ""
    echo "Available combinations:"
    for dir in "$PROJ_DIR"/jdk_*; do
        if [ -d "$dir" ]; then
            dirname=$(basename "$dir")
            echo "  - $dirname"
        fi
    done
else
    echo "========================================"
    echo "WARNING - No JAR files found in dist!"
    echo "========================================"
    exit 1
fi
