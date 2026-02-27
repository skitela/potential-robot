# ARCHITEKTURA_4_AGENTOW_READ_ONLY

## Cel
Zredukowac potrzebe ciaglego monitoringu przez Codexa poprzez lokalna warstwe obserwacyjna i analityczna.

## Boundary model
- Import boundary: denylist runtime trading modules.
- Write boundary: zapis tylko do `outputs/`.
- Data boundary: tylko persisted data (DB/LOGS/META/EVIDENCE/RUN).
- Human-in-the-loop boundary: Codex uruchamiany recznie przez operatora.

## Role agentow
1. Agent Informacyjny - radar operacyjny i alerty.
2. Agent Rozwoju Scalpingu - analityka R&D (netto po kosztach).
3. Agent Rekomendacyjny - synteza i priorytetyzacja rekomendacji.
4. Straznik Spojnosci - drift kontraktow, trigger audytu.

## Wspolny core
- contracts.py
- paths.py
- readonly_adapter.py
- outputs.py
- validators.py
- base_agent.py
- boundaries.py
- stt_normalization.py

## Zasady bezpieczenstwa
- brak importu SafetyBot/EA/bridge,
- brak runtime IPC query,
- brak write do execution-adjacent katalogow,
- brak auto-invocation Codexa.
