# ── Stage 1: base ──────────────────────────────────────────────
FROM python:3.11-slim AS base

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl git xvfb libglib2.0-0 libnss3 libatk1.0-0 libatk-bridge2.0-0 \
        libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
        libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2 \
        libxshmfence1 fonts-noto-cjk xauth x11-apps \
    && rm -rf /var/lib/apt/lists/*

RUN curl -s https://api.github.com/repos/go-gost/gost/releases/latest \
        | grep '"browser_download_url":' \
        | grep 'linux_amd64.tar.gz' \
        | grep -o 'https://[^"]*' \
        | head -n 1 \
        | xargs -I {} curl -sSfL {} \
        | tar zx \
    && mv gost /usr/local/bin/gost \
    && chmod +x /usr/local/bin/gost

WORKDIR /app

COPY webui/requirements.txt webui/

RUN pip install --no-cache-dir \
        requests curl_cffi playwright camoufox[geoip] browserforge mitmproxy pybase64 \
    && pip install --no-cache-dir -r webui/requirements.txt \
    && playwright install firefox chromium \
    && python -m camoufox fetch

# ── Stage 2: webui (frontend build + runtime) ─────────────────
FROM base AS webui

RUN curl -fsSL https://deb.nodesource.com/setup_20.x -o /tmp/nodesource.sh \
    && bash /tmp/nodesource.sh \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g pnpm \
    && rm -f /tmp/nodesource.sh \
    && rm -rf /var/lib/apt/lists/*

COPY webui/frontend/package.json webui/frontend/pnpm-lock.yaml* webui/frontend/
RUN cd webui/frontend && pnpm install --frozen-lockfile

COPY webui/frontend/ webui/frontend/
RUN cd webui/frontend && pnpm build

COPY webui/whatsapp_relay/package.json webui/whatsapp_relay/package-lock.json* webui/whatsapp_relay/
RUN cd webui/whatsapp_relay && npm ci

COPY webui/whatsapp_relay/ webui/whatsapp_relay/

COPY . .

RUN mkdir -p output/logs

EXPOSE 8765
CMD ["python", "-m", "webui.server"]

# ── Stage 3: ml (hCaptcha solver with torch) ──────────────────
FROM base AS ml

RUN pip install --no-cache-dir \
        torch --index-url https://download.pytorch.org/whl/cpu \
    && pip install --no-cache-dir transformers opencv-python-headless pillow numpy

COPY . .

CMD ["python", "CTF-pay/hcaptcha_auto_solver.py"]
