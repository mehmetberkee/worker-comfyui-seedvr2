# Stage 1: Base image with common dependencies
FROM nvidia/cuda:12.6.2-cudnn-runtime-ubuntu22.04 as base

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python 3.12, git and other necessary tools
RUN apt-get update && apt-get install -y \
    software-properties-common \
 && add-apt-repository ppa:deadsnakes/ppa \
 && apt-get update && apt-get install -y \
    python3.12 python3.12-venv python3.12-distutils python3-pip git wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 libxext6 libxrender1 \
 && ln -sf /usr/bin/python3.12 /usr/bin/python \
 && ln -sf /usr/bin/pip3 /usr/bin/pip


# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install comfy-cli (no pip cache)
RUN pip install --no-cache-dir comfy-cli && rm -rf /root/.cache/pip /root/.cache

# Install ComfyUI
RUN /usr/bin/yes | comfy --workspace /comfyui install --cuda-version 12.6 --nvidia --version 0.3.44 \
 && rm -rf /root/.cache

# Change working directory to ComfyUI
WORKDIR /comfyui
# Install torch with CUDA 12.6 compatibility (required for SeedVR2)
RUN pip install --no-cache-dir \
    torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 \
    --index-url https://download.pytorch.org/whl/cu126 \
 && rm -rf /root/.cache/pip /root/.cache

# Install runpod and base deps (no pip cache)
RUN pip install --no-cache-dir runpod requests gguf && rm -rf /root/.cache/pip /root/.cache

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