#!/usr/bin/env bash

echo "--- start.sh Script Başlatıldı ---"

# Use libtcmalloc for better memory management
echo "TCMALLOC için kontrol ediliyor..."
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
if [ -n "$TCMALLOC" ]; then
    export LD_PRELOAD="${TCMALLOC}"
    echo "LD_PRELOAD ayarlandı: ${TCMALLOC}"
else
    echo "libtcmalloc bulunamadı, LD_PRELOAD ayarlanmadı."
fi

echo "Insightface kurulum adımları gereksiz, atlanıyor."

echo "SEEDVR2 model konumu: volume (/runpod-volume/ComfyUI/models/SEEDVR2)"
PERSISTENT_SEEDVR2_DIR="/runpod-volume/ComfyUI/models/SEEDVR2"
LOCAL_SEEDVR2_DIR="/comfyui/models/SEEDVR2"

# Yerel dizin oluşsun ama okuma volume'dan olsun
mkdir -p "${LOCAL_SEEDVR2_DIR}"
if [ -e "${LOCAL_SEEDVR2_DIR}" ] || [ -L "${LOCAL_SEEDVR2_DIR}" ]; then
    rm -rf "${LOCAL_SEEDVR2_DIR}"
fi
ln -s "${PERSISTENT_SEEDVR2_DIR}" "${LOCAL_SEEDVR2_DIR}" || true

# Only link SeedVR2 custom node from volume and install its requirements
PERSISTENT_CUSTOM_NODES_DIR="/runpod-volume/ComfyUI/custom_nodes"
LOCAL_CUSTOM_NODES_DIR="/comfyui/custom_nodes"
SEEDVR2_NODE_NAME="ComfyUI-SeedVR2_VideoUpscaler"
SEEDVR2_NODE_SRC="${PERSISTENT_CUSTOM_NODES_DIR}/${SEEDVR2_NODE_NAME}"
SEEDVR2_NODE_DST="${LOCAL_CUSTOM_NODES_DIR}/${SEEDVR2_NODE_NAME}"

mkdir -p "${LOCAL_CUSTOM_NODES_DIR}"
if [ -d "${SEEDVR2_NODE_SRC}" ]; then
    echo "SeedVR2 custom node bulundu; symlink oluşturuluyor..."
    if [ -e "${SEEDVR2_NODE_DST}" ] || [ -L "${SEEDVR2_NODE_DST}" ]; then
        rm -rf "${SEEDVR2_NODE_DST}"
    fi
    ln -s "${SEEDVR2_NODE_SRC}" "${SEEDVR2_NODE_DST}" || true
    if [ -f "${SEEDVR2_NODE_SRC}/requirements.txt" ]; then
        echo "SeedVR2 requirements yükleniyor: ${SEEDVR2_NODE_SRC}/requirements.txt"
        set -e  # Exit on any error during pip install
        pip install --no-cache-dir -r "${SEEDVR2_NODE_SRC}/requirements.txt"
        set +e
        echo "SeedVR2 requirements başarıyla yüklendi"
    fi
else
    echo "SeedVR2 custom node volume'da bulunamadı: ${SEEDVR2_NODE_SRC}"
fi


# ComfyUI ve RunPod Handler'ı Başlat
# --extra-model-paths-config parametresini ComfyUI komutuna eklediğinizden emin olun!
# Dockerfile'da ./extra_model_paths.yaml olarak kopyalandığı ve WORKDIR /comfyui olduğu için
# doğru yol /comfyui/extra_model_paths.yaml olmalıdır.

COMFYUI_BASE_ARGS="--disable-auto-launch --disable-metadata --extra-model-paths-config /comfyui/extra_model_paths.yaml"
COMFYUI_LOG_FILE="/tmp/comfyui_startup.log"

# Function to check if SeedVR2 node is loaded
check_seedvr2_node() {
    echo "SeedVR2 node yüklenme kontrolü yapılıyor..."
    sleep 5  # Wait for ComfyUI to fully initialize

    # Check if SeedVR2 is in the loaded nodes by looking at ComfyUI's internal state
    python3 -c "
import sys
sys.path.append('/comfyui')
try:
    from nodes import NODE_CLASS_MAPPINGS
    if 'SeedVR2' in NODE_CLASS_MAPPINGS:
        print('✓ SeedVR2 node başarıyla yüklendi: NODE_CLASS_MAPPINGS[\"SeedVR2\"] =', NODE_CLASS_MAPPINGS['SeedVR2'])
    else:
        print('✗ SeedVR2 node yüklenemedi. Mevcut node\'lar:', list(NODE_CLASS_MAPPINGS.keys())[:10], '...')
        sys.exit(1)
except Exception as e:
    print('✗ SeedVR2 node kontrolü başarısız:', str(e))
    sys.exit(1)
"
}

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    echo "runpod-worker-comfy: ComfyUI (API modu) başlatılıyor..."
    python3 /comfyui/main.py ${COMFYUI_BASE_ARGS} --listen &> ${COMFYUI_LOG_FILE} &

    echo "runpod-worker-comfy: RunPod Handler (API modu) başlatılıyor..."
    python3 -u /rp_handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    echo "runpod-worker-comfy: ComfyUI (Worker modu) başlatılıyor..."
    python3 /comfyui/main.py ${COMFYUI_BASE_ARGS} &> ${COMFYUI_LOG_FILE} &

    # Start tailing the log file in background for real-time monitoring
    tail -n +1 -f ${COMFYUI_LOG_FILE} &
    TAIL_PID=$!

    # Check if SeedVR2 node loaded successfully
    check_seedvr2_node

    echo "runpod-worker-comfy: RunPod Handler (Worker modu) başlatılıyor..."
    python3 -u /rp_handler.py &

    # Clean up tail process when RunPod handler exits
    wait $TAIL_PID
fi

echo "--- start.sh Script Tamamlandı ---"