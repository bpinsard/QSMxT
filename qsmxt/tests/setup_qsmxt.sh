#!/usr/bin/env bash
set -e 

# === ACQUIRE LOCK ===

# Set a trap to ensure the lock file is removed even if the script exits unexpectedly
trap 'rm -f "/storage/tmp/qsmxt.lock"; echo "[DEBUG] Lock released due to script exit"; exit' INT TERM EXIT

LOCK_FILE="/storage/tmp/qsmxt.lock"
MAX_WAIT_TIME=10
MIN_WAIT_TIME=5

# Function to generate a random sleep time between MIN_WAIT_TIME and MAX_WAIT_TIME
function random_sleep_time() {
    echo $((RANDOM % (MAX_WAIT_TIME - MIN_WAIT_TIME + 1) + MIN_WAIT_TIME))
}

# Loop until the lock file can be acquired
while true; do
    if [ ! -f "${LOCK_FILE}" ]; then
        touch "${LOCK_FILE}"
        echo "[DEBUG] Lock acquired"
        break
    else
        echo "[DEBUG] Another process is using the resources, waiting..."
        sleep $(random_sleep_time)
    fi
done

# === DETERMINE INSTALL TYPE ===
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 [docker|apptainer]"
    exit 1
fi
CONTAINER_TYPE=$1

# === GET CORRECT BRANCH OF QSMxT REPO ===
echo "GITHUB_HEAD_REF: ${GITHUB_HEAD_REF}"
echo "GITHUB_REF: ${GITHUB_REF}"
echo "GITHUB_REF##*/: ${GITHUB_REF##*/}"

if [ -n "${GITHUB_HEAD_REF}" ]; then
    echo "GITHUB_HEAD_REF DEFINED... USING IT."
    BRANCH=${GITHUB_HEAD_REF}
elif [ -n "${GITHUB_REF##*/}" ]; then
    echo "GITHUB_HEAD_REF UNDEFINED... USING GITHUB_REF##*/"
    BRANCH=${GITHUB_REF##*/}
else
    echo "NEITHER GITHUB_HEAD_REF NOR GITHUB_REF DEFINED. ASSUMING MAIN."
    BRANCH=main
fi

echo "[DEBUG] Checking for existing QSMxT repository in /storage/tmp/QSMxT..."
if [ -d "/storage/tmp/QSMxT" ]; then
    echo "[DEBUG] Repository already exists. Switching to the correct branch and resetting changes..."
    cd /storage/tmp/QSMxT
    git fetch --all
    git reset --hard
else
    echo "[DEBUG] Repository does not exist. Cloning..."
    git clone "https://github.com/QSMxT/QSMxT.git" "/storage/tmp/QSMxT"
fi
echo "[DEBUG] Switching to branch ${BRANCH} and pulling latest changes"
git checkout "${BRANCH}"
git pull origin "${BRANCH}"

echo "[DEBUG] Extracting TEST_CONTAINER_VERSION and TEST_CONTAINER_DATE from docs/_config.yml"
TEST_CONTAINER_VERSION=$(cat /storage/tmp/QSMxT/docs/_config.yml | grep 'TEST_CONTAINER_VERSION' | awk '{print $2}')
TEST_CONTAINER_DATE=$(cat /storage/tmp/QSMxT/docs/_config.yml | grep 'TEST_CONTAINER_DATE' | awk '{print $2}')

# docker container setup
if [ "${CONTAINER_TYPE}" = "docker" ]; then
    echo "[DEBUG] Pulling QSMxT container vnmd/qsmxt:${TEST_CONTAINER_VERSION}_${TEST_CONTAINER_DATE}..."
    sudo docker pull "vnmd/qsmxt_${TEST_CONTAINER_VERSION}:${TEST_CONTAINER_DATE}"

    # Check if the container exists and its image version
    CONTAINER_EXISTS=$(docker ps -a -q -f name=qsmxt-container)
    if [ -n "${CONTAINER_EXISTS}" ]; then
        echo "[DEBUG] qsmxt-container already exists."
        CONTAINER_IMAGE=$(docker inspect qsmxt-container --format='{{.Config.Image}}' 2>/dev/null || echo "")
        if [ "${CONTAINER_IMAGE}" != "vnmd/qsmxt_${TEST_CONTAINER_VERSION}:${TEST_CONTAINER_DATE}" ]; then
            echo "[DEBUG] Existing container has a different version. Stopping, removing it, and its image."
            docker stop qsmxt-container
            docker rm qsmxt-container
            docker rmi "${CONTAINER_IMAGE}"
        fi
    fi

    CONTAINER_EXISTS=$(docker ps -a -q -f name=qsmxt-container)
    if [ ! -n "${CONTAINER_EXISTS}" ]; then
        docker create --name qsmxt-container -it \
            -v /storage/tmp/:/storage/tmp \
            --env WEBDAV_LOGIN="${WEBDAV_LOGIN}" \
            --env WEBDAV_PASSWORD="${WEBDAV_PASSWORD}" \
            --env FREEIMAGE_KEY="${FREEIMAGE_KEY}" \
            --env OSF_TOKEN="${OSF_TOKEN}" \
            --env OSF_USER="${OSF_USER}" \
            --env OSF_PASS="${OSF_PASS}" \
            "vnmd/qsmxt_${TEST_CONTAINER_VERSION}:${TEST_CONTAINER_DATE}" \
            /bin/bash
    fi

    CONTAINER_RUNNING=$(docker ps -q -f name=qsmxt-container)
    if [ ! -n "${CONTAINER_RUNNING}" ]; then
        echo "[DEBUG] Starting QSMxT container"
        docker start qsmxt-container
    fi

    # Run the commands inside the container using docker exec
    echo "[DEBUG] Checking if qsmxt is already installed as a linked installation"
    QSMXT_INSTALL_PATH=$(docker exec qsmxt-container pip show qsmxt | grep 'Location:' | awk '{print $2}')
    echo "[DEBUG] QSMxT installed at ${QSMXT_INSTALL_PATH}"

    if [ "${QSMXT_INSTALL_PATH}" = "/storage/tmp/QSMxT" ]; then
        echo "[DEBUG] QSMxT is already installed as a linked installation."
    else
        echo "[DEBUG] QSMxT is not installed as a linked installation. Reinstalling..."
        docker exec qsmxt-container bash -c "pip uninstall qsmxt -y"
        docker exec qsmxt-container bash -c "pip install -e /storage/tmp/QSMxT"
    fi

    # Test environment variables
    echo "[DEBUG] Testing environment variables"
    echo "--${OSF_TOKEN}--"
    docker exec qsmxt-container bash -c "echo --\"${OSF_TOKEN}\"--"
fi

# apptainer container setup
if [ "${CONTAINER_TYPE}" = "apptainer" ]; then
    echo "[DEBUG] Installing apptainer..."
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:apptainer/ppa
    sudo apt-get update
    sudo apt-get install -y apptainer

    echo "[DEBUG] Install QSMxT via transparent-singularity"
    sudo rm -rf /storage/tmp/test-transparent-singularity
    mkdir -p /storage/tmp/test-transparent-singularity
    cd /storage/tmp/test-transparent-singularity
    export PROD_CONTAINER_VERSION=${TEST_CONTAINER_VERSION}
    export PROD_CONTAINER_DATE=${TEST_CONTAINER_DATE}
    /tmp/QSMxT/docs/_includes/transparent_singularity_install.sh

    echo "[DEBUG] cd qsmxt_* && source activate_qsmxt_${TEST_CONTAINER_VERSION}_${TEST_CONTAINER_DATE}.simg.sh && cd ../"
    cd qsmxt_* && source activate_qsmxt_${TEST_CONTAINER_VERSION}_${TEST_CONTAINER_DATE}.simg.sh && cd ../

    echo "[DEBUG] which julia"
    which julia

    echo "[DEBUG] remove executables we are replacing"
    for f in {python3,python,qsmxt,dicom-sort,dicom-convert}; do
        sudo rm -rf qsmxt_*/${f}
    done

    echo "[DEBUG] Install miniconda"
    sudo rm -rf ~/miniconda3
    /tmp/QSMxT/docs/_includes/miniconda_install.sh
    export PATH="~/miniconda3/envs/qsmxt/bin:${PATH}"

    echo "[DEBUG] Install QSMxT via pip linked installation"
    pip uninstall qsmxt -y
    pip install -e /tmp/QSMxT
fi

rm -f "${LOCK_FILE}"

