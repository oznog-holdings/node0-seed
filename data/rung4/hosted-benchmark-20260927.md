# Rung 4b hosted benchmark, 20260927 (19 requests, all answered by z.ai)

Hosted H53: glm-5.3 on the Coding Plan, through the gateway from the agent box with the agent key, streamed, temperature 0, max_tokens 256 (the local run's prompts and settings; 3 runs per prompt instead of 5). Local L8: the production configuration, measured on compute directly (evidence/20260927-rung4-bench). Time to first token: run 0.

| config | prompt (tokens) | time to first token, run 0 (s) | generation tokens/s (median) | total, run 0 (s) |
|---|---|---|---|---|
| H53 | short (15) | 2.57 | 124.7 | 4.6 |
| H53 | medium (2062) | 1.78 | 225.7 | 3.0 |
| H53 | long (12452) | 2.63 | 256.2 | 3.6 |
| L8 | short (15) | 0.21 | 35.3 | 6.4 |
| L8 | medium (2062) | 5.07 | 31.0 | 13.2 |
| L8 | long (12452) | 70.43 | 18.1 | 84.4 |

| config | tasks t01-t10 correct | wrong | median generated tokens |
|---|---|---|---|
| H53 | 9/10 | t06 balbdees -> baldees | 60 |
| L8 | 9/10 | t06 balbdees -> baldes | 292 |

The gateway adds about 2.5% on a short local request (evidence/20260927-rung4-bench/summary.md), so these hosted times include the gateway and the internet path; the local ones do not. Cost: 0 in the spend log (a subscription); against the plan, 19 of its 60 an hour, plus 1 in the two-key test and 1 in the limit test.

## The two-key test (20260927)

Through the gateway, one request per key. The agent key, allowed the hosted coding model, got
an answer from it (HTTP 200). The monitoring key, not allowed it, was refused by the gateway
(HTTP 403, "key not allowed"). A temporary key limited to one hosted request an hour had its
second request answered by the local model instead, so the gateway's own limit falls back as
designed. The temporary key was deleted afterwards.
