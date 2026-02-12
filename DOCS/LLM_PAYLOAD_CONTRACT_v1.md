# LLM_PAYLOAD_CONTRACT_v1

## Format paczki do LLM (DRY-RUN)

### 1. llm_payload_redacted.txt
- Format: blokowy, każdy plik zaczyna się od `### FILE: <rel_path>`
- Zawartość: zredagowana (secrets, price-like)

### 2. llm_payload_manifest.json
- payload_id: sha256 deterministyczny
- policy_hash: sha256 polityki (sort_keys)
- files: [{rel_path, sha256_raw, bytes, sha256_redacted, secret_redactions, price_redactions, excluded_reason?}]
- totals: included_count, excluded_count, total_bytes
- run_id, mode, tool_versions

### 3. llm_redaction_report.json
- summary + per-file liczniki + powody wykluczeń

### 4. quality_checks.json
- Wyniki 16 cech jakości

### 5. verdict.json
- PASS/FAIL/NEEDS_ATTENTION + powody

## Zakazy
- Brak price-like/secrets w payload
- Brak ścieżek z denylist
- Limity: max_files, max_total_bytes, max_file_bytes
