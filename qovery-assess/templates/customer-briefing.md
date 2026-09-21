# {{organization_name}} — infrastructure review

**Reviewed by:** {{author}}, Qovery
**Date:** {{briefing_date}}
**Based on:** a read-only review of your Qovery organization — clusters, environments,
services, variables and deployment history. Nothing was changed.

---

We went through your setup end to end. Most of it is in good shape, and the parts that are
worth your time come down to {{n_items}} items. They are below, each with what we would do
about it.

{{if_applicable: We have also noted a few questions — places where we can see the
configuration but not the reason behind it, and where your answer changes the
recommendation.}}

---

## What is already working

{{2–4 bullets, specific and evidenced. Not flattery — these are the things not to regress
when the changes below get made.}}

---

## {{1}}. {{short_title}}

**What we found.** {{One sentence, named and specific — the service, the cluster, the
setting. Not "database exposure was observed".}}

**Why it matters for you.** {{The consequence in their terms: what breaks, who notices,
when. If there is a realistic failure sequence, give it in one line.}}

**What we would do.** {{The fix. Where there is a genuine choice, give both options and the
trade-off rather than a verdict.}}

**What we need from you.** {{The decision, the maintenance window, or the answer only they
have. If nothing — say "nothing, we can take this one".}}

---

## {{2}}. {{short_title}}

{{…same four parts. Five or six items total. No "minor items" appendix — if it did not
make the list, it is not in this document.}}

---

## Questions we could not answer from the configuration

{{One line each, with why it is being asked. Examples of the shape:}}

- {{`db-name` accepts public connections. We expect there is a reason — a partner
  integration, a migration tool. Which is it? The answer decides between private
  networking and a source-IP allow-list.}}
- {{`service-name` mounts a {{N}}GB volume. Is that durable data, or scratch space for
  uploads before they go to object storage?}}
- {{Audit logs are available on your organization. Is anyone reading them today, or is that
  something you would want us to help wire up?}}

---

## What we propose

{{The help plan, concretely. Who does what, in what order, by when. This section is the
reason the document exists — every item above should be answerable with "and here is us
doing it with you".}}

| # | Item | Who | When |
|---|---|---|---|
| 1 | {{action}} | {{Qovery / joint / customer}} | {{window}} |

{{If some of this is commercial, say so plainly here rather than leaving it implied.}}

---

*The full technical review behind this summary covers {{total_checks}} checks across
reliability, security, performance, delivery, cost and disaster recovery. Happy to walk
through any part of it in detail — just ask.*
