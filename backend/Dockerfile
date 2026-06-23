# ─────────────────────────────────────────────────────────────────────────────
# Genesis Global CMS — FastAPI Dockerfile
# Used for: local development via docker-compose, optional Render deployment.
# Production on Render uses native Python buildpack (no Docker required).
# ─────────────────────────────────────────────────────────────────────────────

FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Prevent Python from writing .pyc files and enable unbuffered stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Install system dependencies needed for psycopg2 compilation
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies first (layer-cached separately from app code)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application source
COPY . .

# Create a non-root user and hand over ownership
# UID 1000 is the conventional first non-root user on Debian/Ubuntu systems
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Expose the application port
EXPOSE 8000

# Default command — override in docker-compose for --reload during dev
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
