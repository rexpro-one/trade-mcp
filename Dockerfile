# ---- Stage 1: Build ----
FROM python:3.11-slim AS builder

# Install system deps and uv
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh

WORKDIR /app

# Copy everything
COPY . .

# Install the package and its dependencies into the system Python
RUN uv pip install --system .

# ---- Stage 2: Runtime ----
FROM python:3.11-slim

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin/tradingview-mcp /usr/local/bin/tradingview-mcp

# Copy app source
COPY --from=builder /app /app

# Create custom entrypoint script with multi-route handling for Vertex AI
RUN cat << 'EOF' > /app/entrypoint.py
import uvicorn
import starlette.responses
from starlette.applications import Starlette
from starlette.routing import Route, Mount
from tradingview_mcp.server import mcp

# Mengambil aplikasi streamable_http milik FastMCP
mcp_subapp = mcp.streamable_http_app()

async def health(req):
    return starlette.responses.JSONResponse({"status": "ok"})

# Buat wrapper Starlette utama
app = Starlette(
    routes=[
        Route("/health", endpoint=health, methods=["GET"]),
        Mount("/mcp", app=mcp_subapp),
        Mount("/", app=mcp_subapp),
    ]
)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

# Create non-root user for security
RUN useradd -m mcpuser && chown -R mcpuser:mcpuser /app
USER mcpuser

# Expose HTTP port
EXPOSE 8000

# Health check internal Docker
HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# Run entrypoint
CMD ["python3", "/app/entrypoint.py"]
