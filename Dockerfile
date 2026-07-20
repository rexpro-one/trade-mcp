# ---- Stage 1: Build ----
FROM python:3.11-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh

WORKDIR /app
COPY . .
RUN uv pip install --system .

# ---- Stage 2: Runtime ----
FROM python:3.11-slim

WORKDIR /app

COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin/tradingview-mcp /usr/local/bin/tradingview-mcp
COPY --from=builder /app /app

# Entrypoint script: Gunakan mcp.run() bawaan FastMCP dengan mode SSE
RUN cat << 'EOF' > /app/entrypoint.py
import os
from tradingview_mcp.server import mcp

if __name__ == "__main__":
    # Menjalankan FastMCP HTTP/SSE server resmi
    mcp.run(transport="sse", host="0.0.0.0", port=8000)
EOF

# Security & Permissions
RUN useradd -m mcpuser && chown -R mcpuser:mcpuser /app
USER mcpuser

EXPOSE 8000

# Health check ke endpoint SSE default FastMCP
HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/sse')" || exit 1

CMD ["python3", "/app/entrypoint.py"]
