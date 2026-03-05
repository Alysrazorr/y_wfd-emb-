#!/bin/bash

# Docker-based build script for EMB project
# This script builds all jdk_* projects using Docker containers
# and copies the results to the dist folder

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJ_DIR="$(dirname "$SCRIPT_DIR")"

# Parse arguments
PARALLEL_MODE=false
COPY_ONLY=false
JDK_VERSION=""
BUILD_TOOL=""

# Check for flags
for arg in "$@"; do
    if [[ "$arg" == "--parallel" ]] || [[ "$arg" == "-p" ]]; then
        PARALLEL_MODE=true
    elif [[ "$arg" == "--copy-files" ]] || [[ "$arg" == "-c" ]]; then
        COPY_ONLY=true
    else
        if [ -z "$JDK_VERSION" ]; then
            JDK_VERSION="$arg"
        elif [ -z "$BUILD_TOOL" ]; then
            BUILD_TOOL="$arg"
        fi
    fi
done

# Set defaults
JDK_VERSION="${JDK_VERSION:-all}"
BUILD_TOOL="${BUILD_TOOL:-all}"

# Function to display usage
usage() {
    echo "Usage: $0 [JDK_VERSION] [BUILD_TOOL] [OPTIONS]"
    echo ""
    echo "Arguments:"
    echo "  JDK_VERSION  : 8, 11, 17, 21, or 'all' (default: all)"
    echo "  BUILD_TOOL   : maven, gradle, or 'all' (default: all)"
    echo ""
    echo "Options:"
    echo "  --parallel, -p    : Run builds in parallel (faster but uses more resources)"
    echo "  --copy-files, -c  : Only copy additional files (evomaster-agent, jacoco)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Build all projects sequentially"
    echo "  $0 --parallel         # Build all projects in parallel"
    echo "  $0 8 gradle           # Build only JDK 8 Gradle projects"
    echo "  $0 11 maven -p        # Build JDK 11 Maven in parallel mode"
    echo "  $0 all all --parallel # Build everything in parallel"
    echo "  $0 --copy-files       # Only copy evomaster-agent and jacoco files"
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
echo "Mode: $([ "$PARALLEL_MODE" = true ] && echo "PARALLEL ⚡" || echo "Sequential")"
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

# If only copying files, do that and exit
if [ "$COPY_ONLY" = true ]; then
    echo "========================================"
    echo "Copy Additional Files Only Mode"
    echo "========================================"
    echo ""

    mkdir -p "$PROJ_DIR/dist"

    echo "Copying additional files (evomaster-agent, jacoco)..."
    $DOCKER_COMPOSE -f ./scripts/build/docker-compose.build.yml run --rm -T copy-additional-files

    echo ""
    echo "========================================"
    echo "Files copied successfully!"
    echo "========================================"

    if [ -f "$PROJ_DIR/dist/evomaster-agent.jar" ]; then
        echo "evomaster-agent.jar"
        ls -lh "$PROJ_DIR/dist/evomaster-agent.jar"
    fi

    if [ -f "$PROJ_DIR/dist/jacocoagent.jar" ]; then
        echo "jacocoagent.jar"
        ls -lh "$PROJ_DIR/dist/jacocoagent.jar"
    fi

    if [ -f "$PROJ_DIR/dist/jacococli.jar" ]; then
        echo "jacococli.jar"
        ls -lh "$PROJ_DIR/dist/jacococli.jar"
    fi

    exit 0
fi

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
        echo "Tip: Use './scripts/dist-docker.sh <JDK> <TOOL>' for incremental builds"
        echo "     Example: ./scripts/dist-docker.sh 8 gradle"
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
SERVICES_TO_BUILD=()

# Collect services to build
if should_build "8" "maven" && service_exists "8" "maven"; then
    SERVICES_TO_BUILD+=("build-jdk8-maven")
fi

if should_build "8" "gradle" && service_exists "8" "gradle"; then
    SERVICES_TO_BUILD+=("build-jdk8-gradle")
fi

if should_build "11" "maven" && service_exists "11" "maven"; then
    SERVICES_TO_BUILD+=("build-jdk11-maven")
fi

if should_build "11" "gradle" && service_exists "11" "gradle"; then
    SERVICES_TO_BUILD+=("build-jdk11-gradle")
fi

if should_build "17" "maven" && service_exists "17" "maven"; then
    SERVICES_TO_BUILD+=("build-jdk17-maven")
fi

if should_build "17" "gradle" && service_exists "17" "gradle"; then
    SERVICES_TO_BUILD+=("build-jdk17-gradle")
fi

if should_build "21" "maven" && service_exists "21" "maven"; then
    SERVICES_TO_BUILD+=("build-jdk21-maven")
fi

BUILDS_RUN=${#SERVICES_TO_BUILD[@]}

if [ $BUILDS_RUN -eq 0 ]; then
    echo "No services to build!"
else
    echo "Services to build: ${SERVICES_TO_BUILD[@]}"
    echo ""

    # Build Docker images first
    echo "Step 1: Building Docker images..."
    UNIQUE_IMAGES=($(printf '%s\n' "${SERVICES_TO_BUILD[@]}" | sed 's/-maven$//' | sed 's/-gradle$//' | sort -u))
    for service in "${SERVICES_TO_BUILD[@]}"; do
        $DOCKER_COMPOSE -f ./scripts/build/docker-compose.build.yml build "$service" &
    done
    wait
    echo "All Docker images built!"
    echo ""

    # Run builds
    echo "Step 2: Running builds..."
    if [ "$PARALLEL_MODE" = true ]; then
        echo ">>> Running builds in PARALLEL mode..."
        echo ">>> WARNING: This will use significant CPU and RAM!"
        echo ""

        # Start all builds in background
        PIDS=()
        for service in "${SERVICES_TO_BUILD[@]}"; do
            echo "Starting: $service"
            $DOCKER_COMPOSE -f ./scripts/build/docker-compose.build.yml run --rm -T "$service" &
            PIDS+=($!)
        done

        echo ""
        echo "Waiting for all builds to complete..."

        # Wait for all background processes
        FAILED=0
        for i in "${!PIDS[@]}"; do
            wait "${PIDS[$i]}"
            EXIT_CODE=$?
            if [ $EXIT_CODE -ne 0 ]; then
                echo "ERROR: ${SERVICES_TO_BUILD[$i]} failed with exit code $EXIT_CODE"
                FAILED=$((FAILED + 1))
            fi
        done

        if [ $FAILED -gt 0 ]; then
            echo ""
            echo "ERROR: $FAILED build(s) failed!"
            exit 1
        fi

        echo ""
        echo "All parallel builds completed successfully!"
        echo ""
    else
        echo ">>> Running builds in SEQUENTIAL mode..."
        echo ""

        # Run builds one by one
        for service in "${SERVICES_TO_BUILD[@]}"; do
            echo ">>> Building: $service"
            $DOCKER_COMPOSE -f ./scripts/build/docker-compose.build.yml run --rm -T "$service"
            if [ $? -ne 0 ]; then
                echo ""
                echo "ERROR: $service build failed!"
                exit 1
            fi
            echo ""
        done
    fi

    # Copy additional files after all builds
    echo "========================================"
    echo "Copying Additional Files"
    echo "========================================"
    echo ">>> Copying evomaster-agent and jacoco files to dist..."
    $DOCKER_COMPOSE -f ./scripts/build/docker-compose.build.yml run --rm -T copy-additional-files
    echo "Additional files copied!"
    echo ""
fi

echo "========================================"
echo "Cleaning up Docker containers..."
echo "========================================"
$DOCKER_COMPOSE -f ./scripts/build/docker-compose.build.yml down

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
