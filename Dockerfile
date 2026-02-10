# Linux runner image for Magma captain (run.sh) on macOS.
# Run with: docker compose run runner ./run_captain.sh
# Requires Docker socket and workspace mounted; see docker-compose.yml.

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    docker.io \
    inotify-tools \
    util-linux \
    git \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# For exp2json and plot_benchmark
RUN pip3 install --no-cache-dir "pandas>=1.1.0" "matplotlib>=3.3"

WORKDIR /workspace
CMD ["./scripts/run_benchmark.sh"]
