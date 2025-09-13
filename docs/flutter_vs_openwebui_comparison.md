# Conduit (Flutter) vs Open-WebUI Web Client: Architecture Comparison, Issues, and Improvements

## Executive Summary

- Conduit aligns closely with Open-WebUI’s backend contract (auth, chat, tasks, sockets, files, i18n).
- Largest gaps: inconsistent background task flow vs SSE, partial parity for socket event mirroring, file/image handling differences, settings sync, and error UX.
- This document lists concrete issues with targeted improvements that match AGENTS.md guardrails (small, surgical edits, no new deps unless justified).

## Scope and Criteria

- Compared major areas: networking, auth/token, chat send/streaming, sockets, files, settings, i18n, and error handling.
- Cross-referenced key files in `lib/` and `openwebui-src/` to identify parity gaps and opportunities.

---

## Networking & API Layer

- Flutter: `lib/core/services/api_service.dart` uses `Dio` with `ApiAuthInterceptor` and `ApiErrorInterceptor`, plus debug wrappers.
  - Base URL: `ServerConfig.url`.
  - Validates statuses `<400`. Adds custom headers safely.
- Web: `openwebui-src/src/lib/apis/**` uses `fetch`, explicit `Authorization` header, and returns JSON/SSE readers.

Issues
- ApiErrorInterceptor file is referenced but not present in the workspace snapshot (potentially moved/renamed). Risk of inconsistent error shaping.
- `lib/core/services/connectivity_service.dart` defines a simple `dioProvider` that is not wired to project’s configured `Dio`. Possible confusion or unused provider.

Improvements
- Ensure a single `Dio` source of truth. If `dioProvider` is unused, remove it to avoid drift.
- Verify the actual error interceptor path exists and standardizes error payloads (ensure 401, validation errors, and transport errors surface with actionable messages). If missing, add an error transformer consistent with web client’s `handleOpenAIError` patterns.

---

## Authentication & Tokens

- Flutter: `AuthStateManager` persists token via `OptimizedStorageService` and `FlutterSecureStorage`. Adds `Authorization: Bearer` in `ApiAuthInterceptor` only for required or optional endpoints.
- Web: On login, sets `localStorage.token` and uses token in `fetch` headers; `socket` `user-join` is also emitted.

Issues
- Flutter’s auth interceptor strictly blocks required endpoints without token (401 synthesis). Web sometimes tries endpoint and shows backend error. Flutter approach is OK, but ensure optional endpoints are fully listed to match backend behavior.

Improvements
- Keep the strict check but review endpoint lists in `ApiAuthInterceptor` to match Open-WebUI’s optional/required matrix (e.g., config and public assets).
- Add a token-expiry check cadence similar to web layout’s interval if not already running, or rely on backend 401 → logout flow.

---

## Chat Send, Streaming, Tasks, and Sockets

- Web: Primarily streams via SSE (`chatCompletion`) and relays to socket channels; also supports background task flow with `task_id` and event mirroring (`chat-events`, `channel-events`).
- Flutter: `ApiService.sendMessage` supports SSE-like stream but currently forces background tools flow (`useBackgroundTasks = true`), attaches `session_id`/`id`, and polls chat until tool sections are done. Socket integration exists via `SocketService` and `streaming_helper.dart` to listen to lines or JSON payloads.

Issues
- SSE vs Task Mode: Flutter hard-forces background flow, which disables direct SSE streaming and can add latency. Web uses SSE for pure completions and task mode when tools/search/image-gen are active.
- Dynamic Channel Handling: `streaming_helper.dart` has line handlers and `chatHandler`, but suppression flags and switching between SSE and socket content may not mirror all event types from web (`chat:message:delta`, `chat:message:files`, `chat:message:error`, `source/citation`, confirmation, etc.).
- Stop/Cancel: Web manages `taskIds` on active chat to stop. Flutter exposes `stopTask` but does not surface a complete UI flow in providers/widgets here.

Improvements
- Restore dual-path streaming:
  - Use pure SSE (no `session_id`/`id`) when no tools/web-search/image-gen are used to reduce latency and match web UX.
  - Use background task + dynamic channel session only when features require it.
- Expand event handling parity in `streaming_helper.dart` to map Open-WebUI event types to mobile UI updates (files, citations, errors, followups).
- Wire cancel/stop control in UI: keep the task API and expose current `taskIds` per chat to stop ongoing responses.

---

## Files and Attachments

- Web: Uses `/api/v1/files/` with streaming status for processing; images can be inlined in content; shows progress.
- Flutter: `FileAttachmentService` converts images to data-URL instead of uploading; non-images upload via `ApiService.uploadFile` (multipart). `AttachmentUploadQueue` exists for background/offline retries.

Issues
- Image Handling Divergence: Converting images to data URLs increases payload size and memory; web often uploads and references by id/URL, enabling server-side processing (RAG, OCR, etc.).
- Processing Status: Web listens to file processing SSE to surface parse status; Flutter does not reflect live processing feedback after upload.

Improvements
- Prefer consistent behavior: upload images too (like web) and store file `id`, letting server handle compression/processing.
- Optionally implement file processing progress by consuming `/files/{id}/status` SSE (if available) and reflect it in `FileAttachmentWidget`.

---

## Settings and Preferences

- Web: `settings` store persists UI prefs, updates to backend via `updateUserSettings` under `/users/user/settings/update` with `{ ui: settings }`.
- Flutter: `SettingsService` persists locally via `SharedPreferences`; `userSettingsProvider` fetches server settings via `api.getUserSettings()` returning `UserSettings` model.

Issues
- Potential divergence between local-only settings and backend user settings (`ui` namespace). Some settings (e.g., haptics, stream_response default, chat direction) exist on web but not mirrored in Flutter’s `UserSettings`.

Improvements
- Align `UserSettings` fields with backend `ui` structure where applicable; when user is authenticated, prefer server-backed settings for cross-device consistency and fall back to local when offline.
- When settings change, POST updates to backend similar to web (`/users/user/settings/update`). Add a small merge strategy: local-only keys remain local, cross-device keys go to server.

---

## Internationalization (i18n)

- Web: `i18next` with lazy-loaded JSON; language auto-detect and backend default locale; sets `lang` attribute.
- Flutter: `gen-l10n` ARB files with `AppLocalizations`, docs in `docs/localization.md` and CI step.

Issues
- Parity of strings: ensure Flutter ARB keys cover web parity for shared concepts (errors, chat UI hints, settings labels). Some strings appear hardcoded in Flutter widgets (e.g., "Attachments").

Improvements
- Move visible strings to ARB and reuse placeholders/ICU. Mirror important UI preferences and messages so translation workflows match.

---

## Error Handling and UX

- Web: Centralized toast errors (e.g., `handleOpenAIError` path, Error.svelte rendering message/detail with fallbacks).
- Flutter: `ApiErrorInterceptor` (referenced), `ErrorBoundary`, and some ad-hoc `debugPrint`s.

Issues
- Missing or moved `ApiErrorInterceptor` risks inconsistent UX. Error messages from task flow/polling are not always promoted to UI components.

Improvements
- Ensure API errors map to user-friendly messages, with context (network vs auth vs provider error). Surface task/polling errors in the chat UI just like streaming failures.

---

## Connectivity and Offline

- Flutter: `connectivity_service.dart` provides online/offline providers; `AttachmentUploadQueue` retries.
- Web: Browser online/offline events; no background file queue.

Improvements
- Good mobile-first enhancement: keep AttachmentUploadQueue. Consider surfacing an inline banner or per-file retry affordances.

---

## Sockets

- Web: Socket.IO setup in `+layout.svelte`, emits `user-join`, registers `chat-events` and `channel-events`, forwards streamed lines to channel.
- Flutter: `SocketService` mirrors handshake headers, reconnect flow, and event subscription methods.

Issues
- Ensure socket path `/ws/socket.io` and headers match server expectations across reverse proxies; feature flags in mobile to prefer WS-only if environment requires it.

Improvements
- Expose transport mode in settings (already present, `socket_transport_mode`), and surface diagnostics screen to test connectivity.

---

## Security & Privacy

- Flutter: Secure storage for token, avoids logging secrets, custom headers filtered. Web: localStorage for token.

Improvements
- Maintain secure storage for mobile; avoid verbose logging of payloads. Redact tokens in debug logs.

---

## Concrete Action Items (Minimal, Targeted)

1) Streaming mode parity
- In `ApiService.sendMessage`, choose SSE when no tools/web_search/image_generation; use background task session only when required.
- Keep `streaming_helper.dart` suppression flags but extend to support more event types from web.

2) Files
- Upload images via `/api/v1/files/` instead of converting to data URLs. Store `id` and let server serve compressed/derived forms.
- Optionally consume processing status SSE for richer feedback.

3) Settings sync
- Map `UserSettings` to backend `ui` fields; on change, POST to `/users/user/settings/update` similar to web.

4) Error handling
- Ensure `ApiErrorInterceptor` exists and standardizes Dio exceptions. Add chat-level error surfacing in providers/widgets for background task flow.

5) Cleanup and consistency
- Remove or wire the unused `dioProvider` from `connectivity_service.dart`.
- Move literal strings like "Attachments" into ARB files.

6) Diagnostics
- Add a hidden debug screen to exercise socket connectivity and API endpoints (a wrapper exists in `api_service.debugApiEndpoints`).

---

## Deferred / Optional (Non-breaking)

- Stop/Cancel UX parity: expose active `taskIds` and provide a Stop button for ongoing responses.
- Model/tool server parity: ensure `tool_servers` payload and function-calling hints are preserved (already partially implemented).
- Performance: Consider `StreamTransformer` backpressure tuning in `streaming_helper.dart` for low-end devices.

---

## Justification and Guardrails

- Minimal changes; no new dependencies required.
- Aligns with Open-WebUI semantics for better feature parity and user expectations.
- Improves robustness and UX while preserving current architecture and patterns (Riverpod, Dio, interceptors, providers).
