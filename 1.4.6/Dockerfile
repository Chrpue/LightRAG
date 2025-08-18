# Build stage
FROM python:3.11-slim AS builder

RUN sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/debian.sources

WORKDIR /app

ENV RUSTUP_DIST_SERVER=https://mirrors.tuna.tsinghua.edu.cn/rustup \
    RUSTUP_UPDATE_ROOT=https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup

# Install Rust and required build dependencies
RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    pkg-config \
    && rm -rf /var/lib/apt/lists/* \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && . $HOME/.cargo/env


RUN mkdir -p /root/.cargo && \
    echo '[source.crates-io]' > /root/.cargo/config.toml && \
    echo 'replace-with = "tuna"' >> /root/.cargo/config.toml && \
    echo '' >> /root/.cargo/config.toml && \
    echo '[source.tuna]' >> /root/.cargo/config.toml && \
    echo 'registry = "https://mirrors.tuna.tsinghua.edu.cn/git/crates.io-index"' >> /root/.cargo/config.toml

# Copy pyproject.toml and source code for dependency installation
COPY pyproject.toml .
COPY setup.py .
COPY lightrag/ ./lightrag/

# Install dependencies
ENV PATH="/root/.cargo/bin:${PATH}"
RUN pip install --user --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple .
RUN pip install --user --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple .[api]

# Install depndencies for default storage
RUN pip install --user --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple nano-vectordb networkx neo4j
# Install depndencies for default LLM
RUN pip install --user --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple openai ollama tiktoken
# Install depndencies for default document loader
RUN pip install --user --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple pypdf2 python-docx python-pptx openpyxl

# Final stage
FROM python:3.11-slim

RUN sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/debian.sources

RUN apt-get update && apt-get install -y netcat-openbsd && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy only necessary files from builder
COPY --from=builder /root/.local /root/.local
COPY ./lightrag ./lightrag
COPY setup.py .

COPY health_check.sh /app/health_check.sh
RUN chmod +x /app/health_check.sh

RUN pip install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple ".[api]"
RUN python3.11 -m pip install --no-cache-dir --upgrade neo4j -i https://pypi.tuna.tsinghua.edu.cn/simple
RUN python3.11 -m pip install --no-cache-dir gunicorn uvicorn-worker

# Make sure scripts in .local are usable
ENV PATH=/root/.local/bin:$PATH

# Create necessary directories
RUN mkdir -p /app/data/rag_storage /app/data/inputs

# Docker data directories
ENV WORKING_DIR=/app/data/rag_storage
ENV INPUT_DIR=/app/data/inputs

# Expose the default port
EXPOSE 9621

# Set entrypoint
ENTRYPOINT ["python", "-m", "lightrag.api.lightrag_server"]
