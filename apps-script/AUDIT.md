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
