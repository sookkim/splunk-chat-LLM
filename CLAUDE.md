# Project context for Claude Code

RAG chatbot demo (Streamlit → FastAPI → Milvus + BGE reranker → LLM) used to show
**Splunk Observability Cloud** (APM via OTel Collector) and **Splunk Agent Observability**
(formerly Galileo) on a single EC2 host. Forked from `khsydney/splunk-chat-LLM`, branch
`Chat-LLM-Galileo` (upstream last commit 2026-11-01). Owner: SooKyung Kim (Cisco Splunk O11y SA).
Talk to the owner in Korean.

## What this fork changes vs upstream (see `git log`)
1. **LLM: OpenAI → Claude on Amazon Bedrock** (`ChatBedrockConverse`, default
   `global.anthropic.claude-haiku-5-5`, region `ap-northeast-2`). Auth with
   `AWS_BEARER_TOKEN_BEDROCK` (Bedrock long-term API key) or the EC2 instance role.
   Adaptive thinking is disabled (Haiku `disabled`, Sonnet `between_tools`) so replies stay
   plain text; `temperature` is not sent (Claude 5.x may reject it).
2. **Logging SDK: `galileo` → `splunk-ao`** (Agent Observability in O11y Cloud).
   Env: `SPLUNK_AO_REALM`, `SPLUNK_AO_O11Y_TOKEN` (+ optional `SPLUNK_AO_O11Y_API_TOKEN`),
   `SPLUNK_AO_PROJECT`, `SPLUNK_AO_AGENT_STREAM`. Never mix with on-prem vars
   (`SPLUNK_AO_API_KEY`/`SPLUNK_AO_CONSOLE_URL`) — the SDK rejects mixed configs.
   SDK source: https://github.com/splunk/splunk-ao-python (migration guide in
   `splunk-ao-migration-tool/README.md`).
3. **Infra fixes**: MinIO image (deleted from Docker Hub Sep 2026) → `pgsty/silo`;
   collector AppDynamics attributes removed (empty values crashed otelcol); realm and
   namespace from `SPLUNK_REALM` / `SERVICE_NAMESPACE`.
4. **Install fixes**: `unstructured[all-docs]` removed (onnx build needs cmake + endless pip
   backtracking); install with `uv`; `.env.example` has no `<placeholders>` (run.sh `source`s it).

## Environment
- EC2 Ubuntu 24.04, m7i.2xlarge (8 vCPU / 32GB, no GPU), gp3 100GB, Seoul. Python 3.12 venv in `.venv`.
- No GPU needed: only embeddings (BGE-M3) and reranker run locally on CPU; keep
  `RETRIEVAL_TOP_K=20`, `RERANK_TOP_K=5` (upstream 100/70 is too slow on CPU).
- Access UIs over SSH tunnels only (security group: 22 from owner IP). MinIO uses minioadmin/minioadmin.

## Run
```bash
bash scripts/setup_ec2.sh          # once per host
./run.sh infra                     # otelcol, Milvus (etcd/silo/standalone), Redis, Attu
./run.sh index                     # embeds data/docs (first run downloads ~2GB model)
./run.sh app                       # backend :8000, Streamlit :8501, logs in logs/
```
- `./run.sh stop` stops apps **and** infra. To restart only the apps:
  `kill $(lsof -t -i:8000) $(lsof -t -i:8501); ./run.sh app`
- `docker ps` must work without sudo (user in `docker` group, re-login after setup). Don't use sudo with run.sh.

## Status (2026-11-23)
- Verified on the EC2 host: install, infra, indexing (730 chunks), app answering with Claude on Bedrock.
- Verified only statically (py_compile + checked against splunk-ao 0.8.0 source): the
  splunk-ao migration and the collector `${env:VAR:-default}` endpoints. **Next step: run it
  and confirm data in O11y → Agent Observability and APM.**
- Earlier, the galileo SDK got 401 from api.galileo.ai (key was not for that console); moot after migration.
- Agent Control path is untouched/untested; leave `AGENT_CONTROL_URL` empty.

## Debugging checklist
- Backend import error `_ExtendedAttributes`: opentelemetry-api older than sdk →
  `uv pip install "opentelemetry-api==<sdk version>"`.
- `grep -iE "init failed|metrics enabled|401|403" logs/backend.log` — AO init errors are
  logged as warnings and the app keeps running without AO logging.
- 401/403 on sessions/evaluators: the O11y token lacks API permissions → set `SPLUNK_AO_O11Y_API_TOKEN`.
- otelcol: `docker logs otelcol | tail -30`; run.sh recreates it if it exited.
- Bedrock smoke test:
  `python -c "import boto3;print(boto3.client('bedrock-runtime').converse(modelId='global.anthropic.claude-haiku-5-5',messages=[{'role':'user','content':[{'text':'hi'}]}],inferenceConfig={'maxTokens':20},additionalModelRequestFields={'thinking':{'type':'disabled'}})['output'])"`
