# Stage 1: Base image with common dependencies
FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04 as base

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1 
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.10 python3-pip git wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 libxext6 libxrender1 \
 && ln -sf /usr/bin/python3.10 /usr/bin/python \
 && ln -sf /usr/bin/pip3 /usr/bin/pip


# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install comfy-cli (no pip cache)
RUN pip install --no-cache-dir comfy-cli && rm -rf /root/.cache/pip /root/.cache

# Install ComfyUI
RUN /usr/bin/yes | comfy --workspace /comfyui install --cuda-version 11.8 --nvidia --version 0.3.44 \
 && rm -rf /root/.cache

# Change working directory to ComfyUI
WORKDIR /comfyui
# Install runpod
RUN pip install --no-cache-dir runpod requests && rm -rf /root/.cache/pip /root/.cache

# Install SeedVR2 custom node (without auto-downloading models)
RUN mkdir -p /comfyui/custom_nodes \
 && git clone --depth 1 https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler.git \
      /comfyui/custom_nodes/ComfyUI-SeedVR2_VideoUpscaler

RUN if [ -f /comfyui/custom_nodes/ComfyUI-SeedVR2_VideoUpscaler/requirements.txt ]; then \
      pip install --no-cache-dir -r /comfyui/custom_nodes/ComfyUI-SeedVR2_VideoUpscaler/requirements.txt; \
    fi

# Apply GGUF support PR and add gguf package
RUN set -eux; \
    cd /comfyui/custom_nodes/ComfyUI-SeedVR2_VideoUpscaler; \
    git fetch origin pull/78/head:pr-78 || true; \
    git checkout pr-78 || true; \
    pip install --no-cache-dir gguf;

# Patch comfyui_node.py to include GGUF models in dropdown
RUN python - <<'PY'
import re
from pathlib import Path
p = Path('/comfyui/custom_nodes/ComfyUI-SeedVR2_VideoUpscaler/src/interfaces/comfyui_node.py')
text = p.read_text(encoding='utf-8')
pattern = r"(\"model\"\s*:\s*\(\[)([\s\S]*?)(\],\s*\{[\s\S]*?\}\))"
replacement = (
    '"model": (['
    '\n    "seedvr2_ema_3b_fp16.safetensors",\n'
    '    "seedvr2_ema_7b_fp16.safetensors",\n'
    '    "seedvr2_ema_7b_sharp_fp16.safetensors",\n'
    '    "seedvr2_ema_3b_fp8_e4m3fn.safetensors",\n'
    '    "seedvr2_ema_7b_fp8_e4m3fn.safetensors",\n'
    '    "seedvr2_ema_7b_sharp_fp8_e4m3fn.safetensors",\n'
    '    "seedvr2_ema_3b-Q3_K_M.gguf",\n'
    '    "seedvr2_ema_3b-Q4_K_M.gguf",\n'
    '    "seedvr2_ema_3b-Q5_K_M.gguf",\n'
    '    "seedvr2_ema_3b-Q6_K.gguf",\n'
    '    "seedvr2_ema_3b-Q8_0.gguf",\n'
    '    "seedvr2_ema_7b-Q3_K_M.gguf",\n'
    '    "seedvr2_ema_7b-Q4_K_M.gguf",\n'
    '    "seedvr2_ema_7b-Q5_K_M.gguf",\n'
    '    "seedvr2_ema_7b-Q6_K.gguf",\n'
    '    "seedvr2_ema_7b-Q8_0.gguf",\n'
    '    "seedvr2_ema_7b_sharp-Q3_K_M.gguf",\n'
    '    "seedvr2_ema_7b_sharp-Q4_K_M.gguf",\n'
    '    "seedvr2_ema_7b_sharp-Q5_K_M.gguf",\n'
    '    "seedvr2_ema_7b_sharp-Q6_K.gguf",\n'
    '    "seedvr2_ema_7b_sharp-Q8_0.gguf",\n'
    '], {"default": "seedvr2_ema_3b_fp8_e4m3fn.safetensors"}),'
)
new_text = re.sub(pattern, replacement, text, flags=re.M)
if new_text != text:
    p.write_text(new_text, encoding='utf-8')
else:
    print('No model list pattern matched; leaving file unchanged')
PY

# Force offline for HF/Transformers to prevent auto model downloads at runtime
ENV HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1 \
    SEEDVR2_DISABLE_AUTO_DOWNLOAD=1

# Pre-bake SeedVR2 model to avoid cold-start download
# Note: We do not embed the 5GB SeedVR2 model in the image to save CI storage.

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Add scripts
ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
RUN chmod +x /start.sh /restore_snapshot.sh

# Optionally copy the snapshot file
ADD *snapshot*.json /

# Start container
CMD ["/start.sh"]