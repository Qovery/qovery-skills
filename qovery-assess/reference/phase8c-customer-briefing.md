## Phase 8c: The customer briefing

Phase 8 produced the full report. This phase produces the thing that is actually delivered:
**five or six findings, each paired with a concrete offer of help.**

Do not skip this phase on the grounds that the report is well written. The two documents
have different jobs, and a good report is not a short one.

| | Full report (Phase 8) | Briefing (this phase) |
|---|---|---|
| Reader | Qovery — the account team, support, whoever owns the relationship | The customer's engineers and whoever holds their budget |
| Job | Qualify the estate. Find everything, prove each one, score it | Make a small number of risks land, and make the help concrete |
| Length | However long the evidence takes — routinely 40+ findings | 5–6 items |
| Scores, CSV, control appendix | Yes | No |
| Sent as a file | Only if the customer asks for it after the conversation | It *is* the conversation |

### Why the full report is not sent

A team seeing forty findings for the first time cannot rank them. The public production
database and the variable-interpolation nit arrive with the same visual weight, and the
rational response to a list you cannot rank is to act on none of it. Worse, the volume reads
as an indictment: the reliable reaction to "here are forty things wrong with your
infrastructure" is *we clearly need to hire someone for this* — which is the one outcome the
assessment was meant to prevent, and it hands the work to whoever they hire instead.

The briefing inverts both problems. Six items can be held in a head. And every one of them
arrives attached to "here is what we would do about it", which makes Qovery the answer to
the problem the assessment just raised rather than its messenger.

### Selecting the five or six

Severity order from Phase 7 is the starting point, not the answer. Work down the ranked
findings and apply four filters:

1. **Would this wake someone up at 3am?** Data exposure, a single point of failure on the
   revenue path, a database that can be throttled to a stop at peak. These go first and they
   go in whole — never soften a `SC-01` to make the list feel balanced.
2. **Can they act on it inside their current constraints?** A finding that lands during a
   code freeze, or that depends on an architecture decision they have not made yet, is real
   but it is not *this* conversation. Hold it for the next one and say that you are.
3. **Does it collapse into another item?** Three findings that are all "nobody is watching
   production" — no alerting, observability sub-features off, no on-call runbook — are one
   briefing item with three parts, not three of the six slots.
4. **Is it a nit?** Interpolation hygiene, a naming convention, a retention default. These
   are real findings in the report and they are noise in the briefing. Leave them out
   entirely; do not append them as a "minor items" tail, which re-creates the wall of text
   the briefing exists to avoid.

Prefer **one item the customer will be glad you caught** in the six even when a mechanically
stricter list would exclude it. Proactive credibility is the currency this conversation runs
on, and it is spent on the item they had not seen.

### Format

The briefing follows the same format answer as the report (Phase 1.3b). In HTML, reuse
`templates/report.html`: keep the header, the hero and `article.finding`, drop the
scoreband, the table of contents, the appendix and the pillar sections, and end on the
help-plan table. Same components, a tenth of the document. In Markdown, use
`templates/customer-briefing.md`.

Do not build a second visual language for it. The briefing and the report being visibly the
same document family is what makes "the full review is behind this" credible rather than a
claim.

### The shape of each item

Four parts, in this order, no more:

1. **What we found** — one sentence, named and specific. "Your production Postgres accepts
   connections from the public internet", not "database exposure was observed".
2. **Why it matters to you** — the consequence in their business, not the control name.
3. **What we would do** — the actual fix, with the choice left open where there is a real
   choice. A public database has two credible answers, private networking or source-IP
   restriction, and presenting both with the trade-off is what makes it a conversation
   rather than a verdict.
4. **What we need from you** — the decision, the window, or the answer to a question only
   they have.

### Ask, do not assert, where the data does not reach

Several findings are strong on exposure and silent on intent. The assessment can see that a
database is public; it cannot see the partner integration that might be the reason. It can
see persistent volumes; it cannot see whether they hold durable data or scratch writes that
belong in object storage. It can see that audit logging is available; it cannot see whether
anyone reads it.

Put those in the briefing **as questions**, and say why you are asking. Two things follow
from that, both of them good: you find out whether it is a misconfiguration or a constraint
you did not know about, and the customer learns which questions to ask themselves next time
— which is a larger part of the value than any single fix.

Never guess the intent and write it as a finding. A confident wrong assertion about their
architecture costs more credibility than the finding was worth.

### Tone: the offer, not the indictment

The failure mode here is specific and it is easy to walk into. Presenting serious findings
with real conviction, and *stopping there*, tells a team they are out of their depth. They
will agree — and then act on it by looking for help, which may not be you.

So every item ends with Qovery doing something. Not "you should enable alerting" but "we
will set the alerting baseline with you — what pages someone at 3am and what waits until
morning". The technical content is identical; the difference is whether the customer's next
move is toward you or away.

Two rules that follow from this:

- **Commit to what is actually staffed.** An offer you cannot deliver is worse than no
  offer. Where the work is real but unscheduled, say so and put a date on the conversation.
- **Do not moralise.** They made these choices under time pressure and usually for a reason.
  The briefing describes configurations and consequences. It never grades the team.

### Closing the loop

Log which of the six the customer acted on, and check it at the next assessment —
`compare-snapshots.sh` will show it as a closed finding. A briefing item that was fixed
within days is the strongest possible evidence that the selection was right, and it is what
justifies running the exercise again.

It is also the case for offering this as a recurring service rather than a one-off. Note
where the same six items would have been caught automatically: that set is the specification
for what a proactive, scheduled version of this assessment should watch, and a manual pass
per customer does not survive contact with a second one.

### What goes back into the account record

The briefing is a customer artifact; the *selection* is an internal one. Record in the CRM
which findings were surfaced, which were held back and why, and which the customer owns a
decision on. The next person in the account needs to know what has already been said before
they open the same conversation.
