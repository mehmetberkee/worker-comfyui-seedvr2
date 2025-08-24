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


# ComfyUI ve RunPod Handler'ı Başlat
# --extra-model-paths-config parametresini ComfyUI komutuna eklediğinizden emin olun!
# Dockerfile'da ./extra_model_paths.yaml olarak kopyalandığı ve WORKDIR /comfyui olduğu için
# doğru yol /comfyui/extra_model_paths.yaml olmalıdır.

COMFYUI_BASE_ARGS="--disable-auto-launch --disable-metadata --extra-model-paths-config /comfyui/extra_model_paths.yaml"

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    echo "runpod-worker-comfy: ComfyUI (API modu) başlatılıyor..."
    python3 /comfyui/main.py ${COMFYUI_BASE_ARGS} --listen &

    echo "runpod-worker-comfy: RunPod Handler (API modu) başlatılıyor..."
    python3 -u /rp_handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    echo "runpod-worker-comfy: ComfyUI (Worker modu) başlatılıyor..."
    python3 /comfyui/main.py ${COMFYUI_BASE_ARGS} &

    echo "runpod-worker-comfy: RunPod Handler (Worker modu) başlatılıyor..."
    python3 -u /rp_handler.py
fi

echo "--- start.sh Script Tamamlandı ---"