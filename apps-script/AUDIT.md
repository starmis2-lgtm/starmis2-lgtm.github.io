# Where the bulletin data is kept

All data is in the "Production Bulletin – Making & Packing" Google Sheet. Each sheet below has one job.

## 1. BULLETIN AUDIT LOG — the full history (never changed)

- New rows are only **added** at the bottom. Rows are never edited or deleted (the sheet shows a warning if someone tries).
- Every step of a request adds **one row per operation**, with the operation data as it was at that moment.

Columns:

| Column | Meaning |
|---|---|
| Logged At | Date and time of the step |
| Request ID | The request (same ID as in the pending and raw sheets) |
| SRN, Style Name, Category, Type | Which bulletin (Making / Packing, R&D / Production) |
| Event | What happened (list below) |
| By Name, By Email, By Role | Who did it. Role = DEO, Production Manager, GM or Management |
| Op #, Operation, Manpower, Machine, Op/1pc | The operation |
| DEO Time (s) | Time the DEO entered (empty for operations the Production Manager added) |
| PM Time (s) | Time the Production Manager gave |
| Final Time (s) | Time approved by the GM (only on approval rows) |
| Final Time From | Which time the GM used: DEO, Production Manager, Changed by GM (or Added / renamed by GM) |
| Efficiency % | Efficiency set at approval for that manpower |
| Op Status | State of the operation in this step (see below) |
| Photo | Image link of the operation |
| Note / Reason | PM note, reject reason, delete reason, etc. |

Events:

| Event | When | Op Status |
|---|---|---|
| DEO SUBMITTED | DEO sends a new bulletin or an edit (note says "edit of approved bulletin") | Submitted |
| DEO EDITED PENDING | DEO changes a request that is still pending | Submitted (edited) |
| PM REVIEWED | Production Manager gives times, adds or asks to remove operations | Kept / Added by PM / Remove asked by PM |
| DEO CONFIRMED REMOVAL | DEO answers the removal requests | Removed by DEO / Kept by DEO (others: Kept / Added by PM) |
| GM APPROVED | GM approves | Approved (or Added by GM); plus rows with "Removed" for operations removed by the DEO or the GM |
| GM REJECTED / PM REJECTED | Request rejected (reason in Note) | Rejected |
| WITHDRAWN | DEO takes a request back | Withdrawn |
| DELETE REQUESTED / DELETE APPROVED | Delete of a whole bulletin asked / approved | Delete asked / Deleted |
| UNDO EDIT REQUESTED | DEO asks to go back to the earlier version | Submitted (undo) |
| SAVED DIRECTLY BY MANAGEMENT | Management saves without the approval step | Approved (direct) |

If writing the audit log ever fails, the user's action still works; the error goes to the script log and to the ACTIVITY LOG ("AUDIT LOG FAILED").

## 2. BULLETIN RAW DATA — one row per operation per request

- Updated as the request moves on (status, times, decisions). Rows are never deleted.
- Changed operations: the old row is marked "Replaced (...)" and a new row is added.
- Operations that leave a request stay as rows with status **Removed by DEO**, **Removed by GM at approval** or **Removed (edited before approval)**.
- Existing columns did not move. New columns at the end:

| Column | Meaning |
|---|---|
| Added By, Added By Role | Who added the operation (DEO, Production Manager, GM, Management) |
| PM Action | Added / Remove asked / Time given |
| DEO Decision | Removed / Kept (answer to the PM's removal request) |
| PM Name, PM Reviewed At | Production Manager review |
| GM Name, GM Decided At | GM / Management approval or rejection |

Older columns still used: "DEO Entered Time (s)", "Production Manager Time (s)", "Final Time From", "Efficiency %", "Live in Main Sheet".

## 3. PENDING BULLETIN FOR APPROVAL — work in progress

One row per open request (the request as JSON in column A). The row is removed when the GM approves or rejects
or the DEO withdraws. Its history stays in the audit log and the raw sheet.

## 4. Making Bulletin Data / Packing Bulletin Data — final bulletins

Only approved bulletins (time after efficiency). This is what the factory uses. An edit replaces the SRN's rows here;
the earlier version stays in the raw sheet and the audit log.

## 5. ACTIVITY LOG — short text history

One row per user action (login, submit, approve, reject, …) with a short text of what changed. Good for a quick look;
the audit log has the detail per operation.

Other logs: REJECTED BULLETINS (rejected requests and reasons), EFFICIENCY LOG (efficiency per manpower), MIS SUBMIT LOG.

## Which time the GM sees and which time is saved

Checked against the Apps Script code (`pmReviewSubmit` / `deoConfirmRemoval` in Stage.js, `approveBulletin` /
`writeBulletinFinal_` in Approval.js, `effAdjustOps_` in Code.js, `auditFillFinal_` in Audit.js, `rawUpsert_` in Raw.js
and the approval popup in ApprovalJS.html). This is for R&D bulletins (new ones, and edits sent with times @100%).

**a. What the pending request holds after the Production Manager's review**

Each operation keeps three values: `deoTime`, `pmTime` and `time`.

| Operation | `time` | `deoTime` | `pmTime` |
|---|---|---|---|
| Normal operation with a PM time | **DEO time** (not changed) | DEO time | PM time |
| Normal operation without a PM time | DEO time | DEO time | empty |
| Added by the PM | **PM time** | empty | PM time |
| PM asked to remove, DEO kept it | DEO time | DEO time | PM time, if he gave one |

So the PM review never replaces `time`; the PM time is stored next to it. Operations the DEO agreed to remove leave the
request (they are kept in `removedOps` for the logs).

**b. The GM approval popup**

- The final time box is pre-filled with `time`, so with the **DEO time** (the PM time only for operations the PM added).
- Under the box are two buttons: **DEO 60s** and **PM 50s**. Clicking one copies that time into the box (and updates
  target and cost). A button is greyed out when that time is empty. The button that matches the box is highlighted.
- "Use DEO time for all" / "Use PM time for all" do the same for every operation.
- The buttons only show when the PM has reviewed the request.

**c. What is saved when the GM approves**

The value in the box is a time **@100% efficiency**. For each manpower, efficiency = what the GM sets in the popup, else the
efficiency approved before for that SRN, else 100%.

| Where | What is saved |
|---|---|
| Making / Packing Bulletin Data | Time = **box × 100 ÷ efficiency** (2 decimals). Hr Target = 3600 ÷ that time. Cost = (wage ÷ 8) ÷ target. Efficiency column = that efficiency. |
| BULLETIN RAW DATA | Time (s) = box value. "DEO Time @100% (s)" = box value (note: the column name says DEO, but it holds the final time @100%). Efficiency %, Time after Efficiency = box × 100 ÷ efficiency, Cost after Efficiency. "DEO Entered Time (s)" = DEO time, "Production Manager Time (s)" = PM time, "Final Time From". |
| BULLETIN AUDIT LOG (GM APPROVED rows) | DEO Time = DEO time, PM Time = PM time, **Final Time = box value @100%** (not after efficiency), Final Time From, Efficiency %. |

"Final Time From" is worked out by comparing the box to the two times: equal to the DEO time → **DEO**; else equal to the PM
time → **Production Manager**; else **Changed by GM**. If both times are the same, it says DEO. A row the GM added in the
popup says **Added / renamed by GM**.

**d. When the GM types a time that matches neither**

It is saved like any other value: that number @100%, then divided by the efficiency in the main sheet. Final Time From =
**Changed by GM**. The DEO and PM times are still kept in the raw sheet and the audit log, so the change can be seen.

**Example** — DEO 60 s, PM 50 s, efficiency 80%:

| GM does | Box | Main sheet time | Hr target | Audit Final Time | Final Time From |
|---|---|---|---|---|---|
| Approves as shown | 60 | 75 s | 48 | 60 | DEO |
| Clicks PM | 50 | 62.5 s | 57.6 | 50 | Production Manager |
| Types 55 | 55 | 68.75 s | 52.36 | 55 | Changed by GM |

In all three rows the audit log and the raw sheet also keep DEO Time 60 and PM Time 50, Efficiency 80.

Older edit requests (sent before times were @100%) are written to the main sheet as typed and the efficiency is applied
to the sheet afterwards.
