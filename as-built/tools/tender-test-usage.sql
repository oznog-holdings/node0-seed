-- The harness test's usage query (tools/tender-test-archive.py › hermes_usage; the plan's A5.6, written from the
-- rehearsal 20261021). Hermes keeps usage per session and model (session_model_usage), not per call: one row per
-- session (a site-watch run is one session), placed at its first call. The cost is native's own list-price
-- equivalent (cost_source provider_cost_api, cost_status estimated); any other status is unknown (NULL), never zero.
-- Tokens: input_tokens is the uncached input; per-call tokens are in agent.log's "API call #N" lines.
-- Columns: epoch, session, list_usd or NULL, uncached, cache_read, cache_write, output, the model native reported (NULL:
-- Hermes keeps only the requested one), the session's model calls. A session is counted whole in the window of its
-- first call (a site-watch run lasts minutes; one that crosses a window's end is counted in the earlier window).
select u.first_seen, u.session_id,
       case when u.cost_status = 'estimated' and u.cost_source = 'provider_cost_api' then u.estimated_cost_usd end,
       u.input_tokens, u.cache_read_tokens, u.cache_write_tokens, u.output_tokens, NULL, u.api_call_count
from session_model_usage u
where u.billing_provider = 'claude-subscription-directsdk-experimental'
order by u.first_seen;
