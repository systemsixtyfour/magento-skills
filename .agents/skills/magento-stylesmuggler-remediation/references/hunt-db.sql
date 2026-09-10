-- ============================================================================
-- StyleSmuggler (CVE-2026-75650 / APSB26-146)
-- Hunting the payload PERSISTED in the database
-- ============================================================================
-- WHY THIS SCRIPT EXISTS
--
-- The APSB26-146 patch closes EXECUTION, it does not delete what was ALREADY
-- WRITTEN. The exploitation chain puts the template payload into the address
-- fields of a cart (createEmptyCart + setBillingAddressOnCart) and triggers it
-- later with the handlePayflowProResponse mutation. Address fields are STORED.
--
-- Filesystem persistence tends to be weak (partially read-only mounts, deploys
-- that wipe ephemeral directories) but DATABASE persistence is the DURABLE one.
-- If the payload was stored, any future re-render of that address processes it
-- again: transactional emails, reprints, admin views.
--
-- WHY THIS RUNS BEFORE LOOKING AT LOGS: log retention (both the application's
-- own and the observability platform's) is short and rotates; address rows
-- stay. In a real case, the oldest rows in the database moved the exposure
-- window from ~69 hours to ~10 days, and the oldest trace existed ONLY in the
-- database because the observability platform had already rotated the logs for
-- that date. On Cloud, the database is the primary forensic source; the logs
-- are not.
--
-- READ-ONLY. The cleanup statements are at the end, COMMENTED OUT.
--
-- ----------------------------------------------------------------------------
-- STOP - THE AGENT DOES NOT RUN THIS FILE. IT PRODUCES IT AND READS THE OUTPUT.
-- ----------------------------------------------------------------------------
-- The agent's role is to hand the operator the query, say what it does and what
-- output to expect, and INTERPRET THE OUTPUT THE OPERATOR PASTES BACK. Nothing
-- more.
--
--   - The agent NEVER executes anything that writes: DELETE, UPDATE, INSERT,
--     DROP, TRUNCATE, ALTER. The statements at the end of this file are
--     commented out on purpose and stay that way. Uncommenting and running them
--     is the operator's act, with EXPLICIT APPROVAL STEP BY STEP -- never a
--     single blanket approval taken at the start.
--   - NOTHING runs against production, not even these read-only SELECTs,
--     without the human authorizing THAT SPECIFIC query. A read-only query may
--     be PROPOSED; running it is the human's decision. The risk of an
--     unauthorized read is not damage, it is EXPOSURE: in the field incident the
--     query that ran unauthorized was read-only and could not harm anything, but
--     it pulled customer personal data into that session's transcript.
--   - NEVER INVOKE THE PLATFORM CLI. `magento-cloud` and its equivalents on
--     other hosting platforms, any command that opens a database session against
--     a hosted environment, and any SSH session to a node -- none of these are
--     the agent's to run. This is called out by name because the failure mode
--     observed in the field was an agent INFERRING the CLI from a mention of
--     "platform CLI" elsewhere in this skill and running it unprompted.
--   - PREFER A LOCAL DUMP. Run against a copy whenever a copy can answer the
--     question; use production only when the copy genuinely cannot.
--   - BEFORE ANY WRITE there must be a VERIFIED backup -- see RULE 1 of the
--     cleanup section: verified, not assumed -- and the operator confirms it
--     explicitly.
--   - HARD STOP RULE: if the agent has not seen a query's output, the query is
--     NOT DONE. Do not infer row counts, do not assume it ran, do not fill in
--     result sets that were never seen. If the operator did not paste the
--     output, the state is "not verified", not "clean" and not "done". This
--     matters most for Q5 and Q6, where the answer everyone wants is 0 rows:
--     an unseen 0 is not a 0.
--   - INTERPRET, NEVER FABRICATE. The pasted output is the only data. If a
--     query was not run, say it was not run.
-- ----------------------------------------------------------------------------
--
-- HOW IT GETS RUN: every project has its own database access mechanism (platform
-- CLI, SSH tunnel, a client inside a development container). THAT MECHANISM IS
-- OPERATED BY THE HUMAN. Naming it here describes how this file reaches the
-- database; it does NOT authorize the agent to invoke it. The agent hands over
-- the query and reads back the output the operator pastes.
-- The operator feeds this file through stdin. Two details that tend to bite:
--   - the client may be `mariadb` and not `mysql`, depending on the image
--   - run it against a local dump, not against production, when that is enough
-- ============================================================================


-- ============================================================================
-- PERSONAL DATA: ASK FOR THE MINIMUM
-- ============================================================================
-- These three tables (quote_address, customer_address_entity,
-- sales_order_address) hold CUSTOMER PERSONAL DATA: email, first/middle/last
-- name, telephone, fax, street, postcode, city, company and tax id
-- (vat_id), plus free-text customer_notes.
--
-- So each of Q2, Q3 and Q4 comes in TWO VARIANTS:
--   - SWEEP (a) -- the DEFAULT, the one that runs first. Returns IDENTIFIERS AND
--     DATES ONLY. No name, no email, no telephone, no address, no tax id. It
--     answers the only two questions triage needs: WHICH ROWS matched, and WHEN.
--     The WHERE clause still scans every text column -- the payload rotates
--     fields, so narrowing the scan would miss rows. What is minimized is the
--     SELECT, not the search.
--   - INSPECT (b) -- OPT-IN, PER ROW, and commented out. Returns the full detail
--     for ONE id already identified by the sweep, to characterize that row. It
--     RETURNS PERSONAL DATA. It is not needed to size the incident, only to
--     understand a specific row.
-- Q1 is likewise a commented template that returns detail; treat it as opt-in.
--
-- WHY THIS IS STRUCTURED THIS WAY: in the field incident, the query that ran
-- without authorization was read-only and could not damage anything -- but it
-- pulled customer personal data into that session's transcript. The risk of an
-- unauthorized read is not damage, it is EXPOSURE.
--
-- And prefer a LOCAL DUMP over production whenever the dump answers the question
-- just as well. That removes the exposure question entirely.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Q1 - SURGICAL: the specific carts the attacker used  (TEMPLATE)
-- ----------------------------------------------------------------------------
-- WHERE THE IDs COME FROM: the `cart_id` field of the
-- `handlePayflowProResponse` mutations in the project's exception.log
-- (`~/var/log/exception.log`). That cart_id is the cart's masked_id.
--
-- WHY THIS IS THE MOST PRECISE ENTRY POINT: if the logged exception is
-- "Variable must contain instance of \Quote\Payment", it is thrown AFTER the
-- cart is resolved -- which means THAT CART EXISTED.
--
-- Uncomment and paste the masked_id values extracted from the project's log.

-- SELECT '=== Q1: known attacker carts ===' AS section;
--
-- SELECT
--     m.masked_id,
--     m.quote_id,
--     a.address_id,
--     a.address_type,
--     q.created_at        AS quote_created,
--     q.is_active,
--     a.street,
--     a.postcode,
--     a.city,
--     a.region,
--     a.company,
--     a.firstname,
--     a.lastname,
--     a.telephone
-- FROM quote_id_mask m
-- LEFT JOIN quote_address a ON a.quote_id = m.quote_id
-- LEFT JOIN quote         q ON q.entity_id = m.quote_id
-- WHERE m.masked_id IN (
--     /* paste here the masked_id values from the cart_id field of the
--        handlePayflowProResponse mutations in exception.log, one per line */
-- )
-- ORDER BY m.quote_id, a.address_type;

-- Interpretation:
--   0 rows            -> the carts were already harvested by the quote cleanup
--                        cron. Good, but read the caveat below.
--   rows w/o address  -> they created the cart but never set an address.
--   rows WITH '{{'    -> FINDING. Continue with the cleanup section.
--
-- CAVEAT: Q1 returning 0 rows does NOT mean there was no attack. The quote cron
-- harvests old carts, so there is a WINDOW to find them and it closes by itself
-- over time. Q2a does not depend on this list: it scans the whole table and is
-- the one that must always be run.


-- ----------------------------------------------------------------------------
-- Q2 - BROAD: any template directive in CART addresses  [sweep + opt-in detail]
-- ----------------------------------------------------------------------------
-- We do not depend on the cart_id list: we scan the entire table. '{{' is not a
-- LIKE metacharacter, so it matches literally.
--
-- WHY ALL TEXT COLUMNS ARE SCANNED AND NOT JUST `street`: in a real case the
-- payload ROTATED the field carrying the directive between `street`, `company`,
-- `city` and `telephone`. Checking only `street` lets most of them through.

-- (a) SWEEP - DEFAULT. Identifiers and date only, no personal data.

SELECT '=== Q2a: quote_address sweep (identifiers only) ===' AS section;

SELECT a.address_id, a.quote_id, a.address_type, q.created_at
FROM quote_address a
LEFT JOIN quote q ON q.entity_id = a.quote_id
WHERE a.street LIKE '%{{%' OR a.postcode LIKE '%{{%' OR a.city LIKE '%{{%'
   OR a.region LIKE '%{{%' OR a.company LIKE '%{{%' OR a.firstname LIKE '%{{%'
   OR a.middlename LIKE '%{{%' OR a.lastname LIKE '%{{%' OR a.prefix LIKE '%{{%'
   OR a.suffix LIKE '%{{%' OR a.telephone LIKE '%{{%' OR a.fax LIKE '%{{%'
   OR a.email LIKE '%{{%' OR a.vat_id LIKE '%{{%' OR a.customer_notes LIKE '%{{%'
ORDER BY a.address_id DESC
LIMIT 200;

-- Hint for dating the batches: group the `created_at` values this returns. Waves
-- separate by date on their own. Telling one KIT GENERATION from another needs
-- the filler fields (the `email` domain, the `telephone` value) and therefore
-- needs Q2b on a few of the identified rows -- kits use different fillers, and a
-- reserved TLD such as `.invalid` in the email is a strong signal of automated
-- traffic rather than a real customer. Run Q2b only if that distinction actually
-- changes a decision.

-- (b) INSPECT - OPT-IN, ONE ROW AT A TIME. RETURNS PERSONAL DATA.
--     Only to characterize a row the sweep already identified. Not needed to
--     size the incident. Set the address_id from Q2a's output.

-- SELECT '=== Q2b: quote_address detail (PERSONAL DATA) ===' AS section;
--
-- SELECT
--     a.address_id, a.quote_id, a.address_type, a.email,
--     a.street, a.postcode, a.city, a.region, a.company,
--     a.firstname, a.middlename, a.lastname, a.telephone, a.fax, a.vat_id,
--     a.customer_notes, q.created_at AS quote_created
-- FROM quote_address a
-- LEFT JOIN quote q ON q.entity_id = a.quote_id
-- WHERE a.address_id = /* one address_id from Q2a */;


-- ----------------------------------------------------------------------------
-- Q3 - BROAD: stored CUSTOMER addresses  (worse than Q2)  [sweep + opt-in detail]
-- ----------------------------------------------------------------------------
-- These are NOT deleted by the quote cron: they survive indefinitely and get
-- rendered in every transactional email sent to the customer.

-- (a) SWEEP - DEFAULT. Identifiers and dates only, no personal data.

SELECT '=== Q3a: customer_address_entity sweep (identifiers only) ===' AS section;

SELECT entity_id, parent_id AS customer_id, created_at, updated_at
FROM customer_address_entity
WHERE street LIKE '%{{%' OR postcode LIKE '%{{%' OR city LIKE '%{{%'
   OR region LIKE '%{{%' OR company LIKE '%{{%' OR firstname LIKE '%{{%'
   OR middlename LIKE '%{{%' OR lastname LIKE '%{{%' OR prefix LIKE '%{{%'
   OR suffix LIKE '%{{%' OR telephone LIKE '%{{%' OR fax LIKE '%{{%'
   OR vat_id LIKE '%{{%'
ORDER BY entity_id DESC
LIMIT 200;

-- These rows belong to REAL CUSTOMERS, so the detail variant is the one that
-- most needs to stay opt-in: cleanup here neutralizes a field, it does not
-- delete a row (see RULE 3), and that decision needs one row at a time anyway.

-- (b) INSPECT - OPT-IN, ONE ROW AT A TIME. RETURNS PERSONAL DATA.
--     Set the entity_id from Q3a's output.

-- SELECT '=== Q3b: customer_address_entity detail (PERSONAL DATA) ===' AS section;
--
-- SELECT
--     entity_id, parent_id AS customer_id, created_at, updated_at,
--     street, postcode, city, region, company,
--     firstname, middlename, lastname, telephone, fax, vat_id
-- FROM customer_address_entity
-- WHERE entity_id = /* one entity_id from Q3a */;


-- ----------------------------------------------------------------------------
-- Q4 - BROAD: ORDER addresses  (the worst case)  [sweep + opt-in detail]
-- ----------------------------------------------------------------------------
-- If an order was placed with a poisoned address, the order emails
-- (confirmation, shipment, invoice, credit memo) re-render it every time.
--
-- WATCH THE DATE COLUMN: `sales_order_address` has NO `created_at` column.
-- Putting it in the SELECT aborts the query with:
--     ERROR 1054 (42S22): Unknown column 'created_at' in 'SELECT'
-- Verifiable against vendor/magento/module-sales/etc/db_schema.xml: the table
-- has no date column at all. It is dated by JOINing `sales_order`, which does
-- have one. The LEFT JOIN is deliberate: if an order were orphaned, the row
-- must still show up in the finding, with `created_at` as NULL.

-- (a) SWEEP - DEFAULT. Identifiers and date only, no personal data.

SELECT '=== Q4a: sales_order_address sweep (identifiers only) ===' AS section;

SELECT a.entity_id, a.parent_id AS order_id, a.address_type, o.created_at
FROM sales_order_address a
LEFT JOIN sales_order o ON o.entity_id = a.parent_id
WHERE a.street LIKE '%{{%' OR a.postcode LIKE '%{{%' OR a.city LIKE '%{{%'
   OR a.region LIKE '%{{%' OR a.company LIKE '%{{%' OR a.firstname LIKE '%{{%'
   OR a.middlename LIKE '%{{%' OR a.lastname LIKE '%{{%' OR a.prefix LIKE '%{{%'
   OR a.suffix LIKE '%{{%' OR a.telephone LIKE '%{{%' OR a.fax LIKE '%{{%'
   OR a.vat_id LIKE '%{{%'
ORDER BY a.entity_id DESC LIMIT 200;

-- (b) INSPECT - OPT-IN, ONE ROW AT A TIME. RETURNS PERSONAL DATA.
--     These rows are accounting records: the detail is for the conversation with
--     the business (RULE 3), which is per order, not per table. Set the
--     entity_id from Q4a's output.

-- SELECT '=== Q4b: sales_order_address detail (PERSONAL DATA) ===' AS section;
--
-- SELECT a.entity_id, a.parent_id AS order_id, a.address_type, o.created_at,
--        a.street, a.postcode, a.city, a.region, a.company,
--        a.firstname, a.middlename, a.lastname, a.telephone, a.fax, a.vat_id
-- FROM sales_order_address a
-- LEFT JOIN sales_order o ON o.entity_id = a.parent_id
-- WHERE a.entity_id = /* one entity_id from Q4a */;


-- ----------------------------------------------------------------------------
-- Q5 - TOTALS: count per table, to size the problem before touching anything
-- ----------------------------------------------------------------------------
-- This is also the closure criterion (a) of the skill: the incident is not
-- closed until this query returns 0 for all three tables.

SELECT '=== Q5: totals ===' AS section;

SELECT 'quote_address' AS table_name, COUNT(*) AS rows_with_directive
FROM quote_address
WHERE street LIKE '%{{%' OR postcode LIKE '%{{%' OR city LIKE '%{{%'
   OR region LIKE '%{{%' OR company LIKE '%{{%' OR firstname LIKE '%{{%'
   OR lastname LIKE '%{{%' OR telephone LIKE '%{{%' OR vat_id LIKE '%{{%'
   OR customer_notes LIKE '%{{%'
UNION ALL
SELECT 'customer_address_entity', COUNT(*)
FROM customer_address_entity
WHERE street LIKE '%{{%' OR postcode LIKE '%{{%' OR city LIKE '%{{%'
   OR region LIKE '%{{%' OR company LIKE '%{{%' OR firstname LIKE '%{{%'
   OR lastname LIKE '%{{%' OR telephone LIKE '%{{%' OR vat_id LIKE '%{{%'
UNION ALL
SELECT 'sales_order_address', COUNT(*)
FROM sales_order_address
WHERE street LIKE '%{{%' OR postcode LIKE '%{{%' OR city LIKE '%{{%'
   OR region LIKE '%{{%' OR company LIKE '%{{%' OR firstname LIKE '%{{%'
   OR lastname LIKE '%{{%' OR telephone LIKE '%{{%' OR vat_id LIKE '%{{%';


-- ----------------------------------------------------------------------------
-- Q7 - SUPPORT FOR STEP 2: the project's real store codes
-- ----------------------------------------------------------------------------
-- Run this BEFORE putting the CDN/WAF allowlist rule of step 2a into enforce
-- mode. The rule rejects any `Store` header that does not look like a legal
-- store code; if a code in use did not match the allowlist charset, the rule
-- would break a working storefront. Confirm the real list first.

SELECT '=== Q7: store codes in use ===' AS section;

SELECT store_id, code, is_active FROM store;


-- ============================================================================
-- CLEANUP - COMMENTED OUT ON PURPOSE. DO NOT UNCOMMENT WITHOUT READING THIS.
-- ============================================================================
--
-- RULE 1: dump the database BEFORE any write, using the project's own backup
--     mechanism. Without a prior dump, nothing gets written.
--
-- RULE 2: review EVERY row by hand first. '{{' in an address is almost
--     certainly the attack, but a real customer may have typed '{{' into
--     customer_notes or company. Deleting a real customer's data over a false
--     positive is worse than the payload.
--
-- RULE 3: distinguish the three cases:
--     - quote_address of an attacker cart      -> delete the whole quote
--     - customer_address_entity of a real user -> neutralize just the field
--     - sales_order_address                    -> do NOT touch without
--       agreement from the business: it is an accounting record. Neutralize the
--       field, never the row.
--
-- RULE 4: neutralize != delete. Breaking the directive is enough for the filter
--     not to recognize it. Evidence is preserved and can be audited later.
--
-- SAFETY CRITERION before deleting a quote, verified row by row:
--     - no `customer_id`                      -> there is no real customer
--                                                behind it
--     - no associated order                   -> no accounting record depends
--                                                on the row
--     - email on a reserved TLD (.invalid)    -> cannot be a real address
-- With all three met, deleting the whole quote is safe: it cascades by FK to
-- quote_address, quote_item and quote_id_mask. If any is missing, do NOT delete.

-- -- (a) Delete the attacker carts identified in Q1/Q2a.
-- --     Cascades to quote_address, quote_item, quote_id_mask by FK.
-- DELETE FROM quote
-- WHERE entity_id IN ( /* paste here ONLY the entity_id values that passed the
--                        safety criterion of RULES 2 and 3, one by one */ );

-- -- (b) Neutralize the directive in a real customer's address, preserving the
-- --     rest of the value. Adjust entity_id and column.
-- UPDATE customer_address_entity
-- SET street   = REPLACE(street,   '{{', '(( '),
--     postcode = REPLACE(postcode, '{{', '(( ')
-- WHERE entity_id IN ( /* paste here the entity_id values confirmed in Q3a */ );

-- -- (c) Verification afterwards: run Q6 (below) and Q5. Both must return 0 rows
-- --     for the cleaned tables.


-- ----------------------------------------------------------------------------
-- Q6 - POST-CLEANUP VERIFICATION  (must return 0 rows)
-- ----------------------------------------------------------------------------
-- WATCH THE PATTERN. In a real case, the verification query was run with the
-- last predicate written as
--     customer_notes LIKE '%{12}%'
-- which is a TYPO and matches nothing. The correct pattern is '%{{%'.
--
-- A typo like that returns 0 rows and reads as "it is clean": it is the WORST
-- possible failure mode in a verification, because it confirms exactly what you
-- want to read while leaving the column genuinely unverified. Before believing
-- a 0, check that ALL predicates use '%{{%' -- and, better, validate the query
-- once against a row that does carry the payload, to confirm it matches.
--
-- Q6 MIRRORS Q2a, IDENTIFIERS ONLY, for the same reason: it returns no personal
-- data. That is not a compromise here -- the question this query answers is
-- "how many rows still match", and an id plus a date answers it completely. If a
-- surviving row has to be characterized, that is Q2b on that one address_id.
-- This query is the one run most often (after each cleanup pass), so it is the
-- one where a full column list would leak the most.

SELECT '=== Q6: post-cleanup verification (must return 0 rows) ===' AS section;

SELECT a.address_id, a.quote_id, a.address_type, q.created_at
FROM quote_address a
LEFT JOIN quote q ON q.entity_id = a.quote_id
WHERE a.street LIKE '%{{%' OR a.postcode LIKE '%{{%' OR a.city LIKE '%{{%'
   OR a.region LIKE '%{{%' OR a.company LIKE '%{{%' OR a.firstname LIKE '%{{%'
   OR a.middlename LIKE '%{{%' OR a.lastname LIKE '%{{%' OR a.prefix LIKE '%{{%'
   OR a.suffix LIKE '%{{%' OR a.telephone LIKE '%{{%' OR a.fax LIKE '%{{%'
   OR a.email LIKE '%{{%' OR a.vat_id LIKE '%{{%' OR a.customer_notes LIKE '%{{%'
ORDER BY a.address_id DESC
LIMIT 200;


-- ============================================================================
-- NOTE ON SCOPE
-- ============================================================================
-- This script covers the address tables, which is where the documented chain
-- comes in. It is NOT an exhaustive sweep of "every text field Magento passes
-- through the template filter". If Q2a/Q3a/Q4a come back positive, extend to
-- cms_page.content, cms_block.content, email_template.template_text and
-- core_config_data.value before calling the incident closed.
-- ============================================================================
