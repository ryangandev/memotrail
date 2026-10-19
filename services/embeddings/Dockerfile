# MemoTrail's own embedding service: Hugging Face Text Embeddings Inference (CPU) with the
# model weights baked in, so the running container never contacts Hugging Face.
# It turns text into vectors and holds no database credentials.
#
# The model below must match apps/web/src/lib/search/semantic-model.json; a Web unit test
# checks that. To change models, edit that file first, then these three lines.

# Pinned TEI CPU image (tag cpu-1.8, multi-architecture index digest).
ARG TEI_IMAGE=ghcr.io/huggingface/text-embeddings-inference:cpu-1.8@sha256:8de25e75ce39617f17f2f6c77d60a4f75b65e779ed5005420eb1400072a15c1c

FROM python:3.12-slim AS weights
ARG MODEL_ID=Qwen/Qwen3-Embedding-0.6B
ARG MODEL_REVISION=97b0c614be4d77ee51c0cef4e5f07c00f9eb65b3
RUN pip install --no-cache-dir "huggingface_hub>=0.30,<1"
RUN python -c "import os; from huggingface_hub import snapshot_download; snapshot_download(repo_id=os.environ['MODEL_ID'], revision=os.environ['MODEL_REVISION'], local_dir='/models/model', allow_patterns=['*.json', '*.txt', '*.safetensors', '1_Pooling/*'])"

FROM ${TEI_IMAGE}
COPY --from=weights /models/model /models/model

# Never log request bodies: they hold the user's queries and writing.
ENV RUST_LOG=warn \
    HF_HUB_OFFLINE=1 \
    HUGGINGFACE_HUB_CACHE=/tmp/hf-cache

EXPOSE 8080
# The API key comes from the API_KEY environment variable (a Fly secret).
# The served name is the label stored with every vector (SEMANTIC_MODEL in the Web app).
# Verify these flags with `--help` when the TEI version changes.
ENTRYPOINT ["text-embeddings-router"]
CMD ["--model-id", "/models/model", \
     "--served-model-name", "Qwen/Qwen3-Embedding-0.6B@97b0c614be4d", \
     "--port", "8080", \
     "--max-client-batch-size", "32", \
     "--auto-truncate"]
