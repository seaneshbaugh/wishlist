# Wishlist TODOs

## Finish test coverage of existing features

- [x] Add list-item system workflows: create from each new-item form, reset only the submitted form, edit/cancel/delete, and targeted validation replacement preserving the other form.
- [x] Add purchase system workflows: create/edit/delete, targeted validation failures, and another purchase after a historical purchase reveals.
- [x] Add request coverage for authentication, foreign-owner mutations, nested resource mismatches, public/private list access, hidden items, and reveal-dependent purchase permissions.
- [x] Add model coverage for item visibility, reveal boundaries, purchase quantity limits, multiple historical purchases, and one unrevealed purchase per user/item.
- [x] Add list-item reorder request coverage; existing tests only cover list reorder. Reject malformed values and foreign/missing/duplicate IDs.
- [x] Make the browser reorder test wait for persistence before inspecting database positions; DOM changes happen before fetch completes.

## Review findings to fix after regression tests

- [x] Fix `ListItem#unrevealed_purchase_for`: `purchase.find` must use `purchases`. Currently non-owner pages with visible items raise.
- [x] Handle missing/invalid reveal dates before calling `revealed?` during purchase validation. An unsaved purchase with a user/item and nil reveal date raises instead of returning validation errors.
- [x] Enforce item visibility on purchase creation. The current item lookup checks list access but accepts hidden item IDs.
- [x] Fix `dom_id` in `ListItemsController#update` failure handling; controller code calls an unavailable view helper directly, so invalid Turbo updates raise instead of rendering errors.
- [x] Fix initial ordering: database defaults give new lists/items position 0, so callbacks guarded by `position.nil?` skip assigning the next position.
- [x] Remove the index count N+1: compute visible-item counts grouped by list in one query. Preloading `list_items` alone will not fix `.visible_to(current_user).size`, which creates a scoped relation per list.
- [x] Recheck purchase authorization after acquiring the item lock and reload purchase state for update/delete. Authorization currently runs before waiting for the lock, so the reveal boundary or concurrent changes can invalidate its decision.
- [x] Define behavior when an owner lowers item quantity below existing purchased quantity; currently possible and can prevent unrelated purchase edits.
- [x] Fix list destroy failure rendering: `lists/show` expects item collections and a new-item form object that this path does not load.
- [x] Tighten reorder numeric input validation; `to_i` accepts malformed strings and nil as integers.
- [x] Remove unused `list_item_form_controller.js`; no current view references the old custom-fetch controller.

## Later product work

- [x] Implement friendships and friendship-based visibility (manual beta/deployment checks remain below).
- [x] Add invitation-only signup and invitation acceptance for existing users (manual Mailpit/beta checks remain below).
- [ ] Implement revealed purchase details/anonymous attribution and owner deletion controls if desired; current owner UI displays only purchased quantities.
- [x] Improve README setup documentation for Docker on Fedora and Ubuntu/WSL.
- [x] Choose the existing dynamic-sites DigitalOcean droplet and Rancher Machine workflow for beta (deployment plan below).
- [x] Correct the production primary database key to `database` in `config/database.yml`.
- [x] Configure production mail sender/URL/SMTP settings as part of the deployment plan below.

## Viewer sorting: agreed behavior and implementation plan

### Product rules

- Sorting controls appear only when viewing a friend's list. Owners retain the existing priority groups and drag-and-drop ordering.
- Use one accessible "Sort by" dropdown above the items with options "Priority", "Price: low to high", and "Price: high to low". Priority is the default and restores priority groups with their manual item ordering; a separate Clear Sorting button is unnecessary.
- Price sorting produces a single flat list across all priority groups. Sort by per-item price, placing items without a price last in both directions. Zero is a real price. Break equal-price ties (including unpriced items) by priority, then manual position, then item ID for deterministic ordering.
- In the flat view, display each item's priority as a small label next to the item. Keep the default grouped view's existing presentation.
- Store the selection in a shareable, bookmarkable query parameter, such as `sort=price_asc` or `sort=price_desc`. The ordinary list URL means Priority; selecting Priority removes the sort parameter.
- Every user-initiated sort change adds a browser history entry. Back and Forward restore the selection, ordering, grouping, and labels without a full-page refresh. Reloading or opening the URL directly reproduces the view.
- Preserve sorting after purchase creation, editing, deletion, and validation failures. Sorting never changes stored item priority/position or alters item visibility, list access, or purchase authorization.
- Start with price only. Future date sorting means item `created_at`, not `updated_at`; name/date options are deferred until the price approach is proven.

### 1. Server ordering and rendering

- [x] Parse an explicit allowlist of sort values with a Priority fallback for missing/unknown values. Do not interpolate arbitrary query input into SQL. Ignore sorting on owner views.
- [x] Apply ordering to the existing authorized, viewer-visible item relation. Price order must replace the default priority-first order, handle NULL prices last in both directions, and retain purchases preloading without N+1 queries.
- [x] Render grouped sections for Priority and a flat collection for price sorting, reusing the existing item markup and purchase controls. Keep DOM identities stable and show priority labels only in the flat view.
- [x] Keep the item summary/count/timestamp based on the same visible collection, regardless of its order. Preserve empty-list behavior.

### 2. Dropdown, Turbo, and browser history

- [ ] Add the labeled dropdown for non-owners with the current selection derived from the URL. Use a GET form and normal Turbo navigation; keep Stimulus limited to submitting the selection if needed.
- [ ] Choose a Turbo Frame or equivalent Turbo navigation boundary that refreshes the controls and list together while promoting sort navigation to browser history (`advance`). Verify actual Back/Forward restoration rather than assuming partial replacement updates history.
- [ ] Ensure direct/full-page requests and frame requests render correctly, including an empty list. Priority navigation should produce the ordinary list URL without stale sort parameters.
- [ ] Carry the allowlisted sort context through purchase forms and success/error responses, including HTML redirect fallbacks. Subsequent mutations must preserve sorting, flat/grouped presentation, dropdown selection, priority labels, and the current URL without adding spurious sort history entries.
- [ ] Keep targeted purchase validation replacement and submitted values intact. A successful purchase that removes an item from the viewer-visible collection must leave the remaining items correctly sorted.

### 3. Tests and verification

- [ ] Request tests: ascending/descending per-item prices across priorities; NULL-last in both directions; zero prices; equal-price priority/manual-order ties; default/unknown sort values; empty lists; and owner views retaining manual ordering. Verify sorting does not persist position/priority changes.
- [ ] Access/visibility regression tests: hidden and fulfilled items stay excluded as appropriate, historical purchasers retain existing visibility, and unrelated/former friends and private lists remain inaccessible for sorted URLs.
- [ ] Purchase request tests: retain sort on successful create/update/delete and HTML redirects, and preserve targeted validation errors. Verify each rendered list uses the requested order after visibility changes.
- [ ] System tests: select both price directions, verify flat ordering and priority labels, return to Priority grouping, and verify the URL and dropdown at each step. Include a tie and an unpriced item without testing every possible combination in the browser.
- [ ] System tests: exercise multiple sort changes followed by Back and Forward, reload a sorted URL, and directly open a sorted URL. Confirm Turbo navigation avoids a full-page refresh and restores consistent controls and content.
- [ ] System tests: create/edit/delete a purchase while sorted and submit an invalid purchase form; confirm the selection/URL/order persist and successful mutations still update the item summary.
- [ ] Retain existing list, item, purchase, and owner drag-and-drop coverage. Verify query counts stay bounded as the number of items grows; run relevant request/system suites and style checks.
- [ ] Manually review the dropdown, labels, and purchase forms at narrow/mobile widths before deploying. Reconsider priority-label styling if it looks cluttered.

## Friendships: agreed behavior and implementation plan

### Product rules

- Friendship is mutual after explicit acceptance; pending requests grant no access. Friendship is not transitive, and users cannot browse another person's friends.
- A public list means visible to accepted friends. Owners retain access to all their own lists. Private lists remain owner-only.
- Request friendship by email, with no searchable user directory or outgoing-request list. Do not disclose whether an otherwise unknown email belongs to an account.
- Incoming requests identify the requester so the recipient can recognize them. Use their username for display; never expose unrelated users or their lists through the request page.
- Only the recipient may accept or decline a pending request. Declining deletes the row without notifying the requester. Either participant may remove an accepted friendship.
- Crossed requests require explicit acceptance: if Alice has already requested Bob, Bob submitting Alice's email gets a message pointing to his incoming request and an acceptance control. This may identify Alice because she has already disclosed herself through that incoming request. Do not automatically accept.
- Removing a friendship immediately revokes access on subsequent requests to both participants' lists and purchases, including purchases they previously made. Preserve purchase records and historical quantities; revocation does not cancel a gift or erase history. Content already viewed cannot be withdrawn.
- Send email notifications for new requests and acceptance. Do not send decline/removal notifications. Repeated submissions must not resend request emails or create duplicates.
- No rejection history, blocking, request expiration, or outgoing-request management for beta. Deletion permits a later new request.

### 1. Schema and model

- [x] Fill in the existing uncommitted Friendship migration/model rather than generate a second pair.
- [x] Add required `requester_id` and `recipient_id` foreign keys to users, nullable `accepted_at`, and the existing timestamps. Null acceptance means pending; a timestamp means accepted.
- [x] Add database and model checks preventing self-friendship. Add a unique expression index on `LEAST(requester_id, recipient_id), GREATEST(requester_id, recipient_id)` to prohibit duplicate pairs in either direction, including simultaneous crossed requests.
- [x] Index participant lookups and add explicit `requester`/`recipient` associations. Ensure deleting either user removes their pending and accepted friendship rows without deleting the other user.
- [x] Add incoming/outgoing association names, pending/accepted scopes, and a `User#friends` relation covering either side of accepted friendships. Keep it chainable for ordering and grouped list counts. Do not create reciprocal rows or a separate request model.
- [x] Keep participants immutable through controller parameters. Acceptance only changes `accepted_at`; removal/decline deletes the row.


### 2. Request lifecycle and authorization

- [x] Add authenticated FriendsController index and FriendshipsController create, incoming-requests, accept, and destroy actions. Use `/friends` for accepted friends, `/friends/:friend_id/lists` for browsing, and friendship IDs for relationship actions. No self friend URLs or profile route yet; owner purchase deletion uses `/lists/:list_id/purchases/:id`.
- [x] Create accepts only an email address: requester is `current_user`; resolve recipient using Devise-compatible trimming/case normalization and their current confirmed email. Do not match a pending `unconfirmed_email` or create requests for unconfirmed accounts.
- [x] For unknown emails and newly sent requests, return the same generic response, e.g. "If that email belongs to an eligible account, a friend request will be sent." Return the same response for repeated outgoing requests; do not expose recipient identifiers or conditionally reveal an outgoing record in HTML/Turbo responses.
- [x] Handle self-requests and already accepted friendships deliberately without creating records or emails. Information about the current user or an existing friend may be shown without exposing a new account.
- [x] On crossed requests, link to the existing incoming request. Opening the link is read-only; acceptance uses a button submitting PATCH, never a GET that changes state.
- [x] Scope acceptance to the current recipient's pending requests. Lock the friendship and check its state before transitioning so concurrent/repeated acceptance cannot send duplicate notifications.
- [x] Scope decline to the current recipient's pending requests and removal to accepted friendships involving the current user. Unrelated users and guessed IDs get 404. Old links after decline/removal should fail cleanly.
- [x] Handle database uniqueness races deliberately: reload the existing pair and apply the same duplicate/crossed-request rules rather than returning a server error or accepting implicitly.
- [x] Prepare and render responses outside transactions; keep controller flow explicit.
- [x] Enqueue notifications only for successful new records/state transitions after commit. All delivery occurs in background jobs.

### 3. Email notifications

- [x] Add friendship request and acceptance mailer actions with HTML/text templates and localized subjects/messages, following existing mail/job conventions.
- [x] New-request email goes to the recipient and identifies the requester. Acceptance email goes to the original requester and identifies the accepting friend. Do not include wishlist or purchase details.
- [x] Link request emails to authenticated incoming requests and acceptance emails to the friend's accessible lists. Links must require login as the appropriate user; forwarded email links grant no authority.
- [x] Enqueue once per actual request/acceptance transition. No email for unknown addresses, invalid/self requests, duplicate submissions, failed authorization, or declined requests.
- [x] Handle queued work gracefully when a friendship or user has been deleted; do not resurrect relationships or send actionable request messages for requests already resolved. A failed email must not undo a saved friendship transition.
- [x] Verify request and acceptance delivery through background jobs to local Mailpit. Production worker configuration consumes the `friendship_notification` queue via its existing `queues: "*"` setting; deployment instructions are in README.md.
- [ ] At deployment, verify a live production worker and SMTP/URL/sender configuration on the target host (hosting work; no production environment exists yet).

### 4. Apply access rules throughout the application

- [x] Keep list access encapsulated in the existing lookup scopes: self sees own lists; accepted friends see friends-visible lists; pending users, former friends, and unrelated users receive 404 for direct access.
- [x] Restrict user lookup itself for user/list/purchase routes to self or accepted friends, so unknown and inaccessible usernames do not produce distinguishable application responses.
- [x] Remove the global users index route/action and replace navbar links with Friends. Remove unused standalone user profile routes/actions if they serve no remaining purpose; replace nested user/list URLs with friend/list URLs and scoped access checks.
- [x] Apply the same parent-access rule to list indexes, list show, and purchase create/update/delete. Historical purchase-based item visibility never overrides missing friendship or a private list. Existing purchase operation predicates remain unchanged once parent access succeeds.
- [x] Retain the current item visibility rules within an accessible list, including owner visibility, hidden items, fulfillment, and historical purchaser visibility. Retain grouped visible-item counts.
- [x] Relabel Public as Friends and explain the distinction from Private in list forms/status text. Keep the existing boolean storage for this feature unless a concrete need for migration emerges.
- [x] Do not create default friendships between existing users or silently expose lists as part of deployment. Users establish relationships through the new flow.


### 5. UI and Turbo behavior

Friendship forms use targeted Turbo Stream responses with HTML redirect fallbacks. Crossed requests deliberately navigate to the incoming-requests page; acceptance and removal update the current page without clearing email drafts.
- [x] Friends index: alphabetized accepted friends, including friends with zero visible lists; grouped count of friends-visible lists; link each friend directly to their lists; clear empty state.
- [x] Add the email request form and a link to the incoming-requests page. Do not add user search, suggestions, mutual-friend counts, or outgoing requests.
- [x] Incoming requests page: recognizable sender, Accept and Decline controls, and an empty state. Crossed-request responses link here or present the same explicitly authorized acceptance control.
- [x] Add friendship removal with a clear Turbo confirmation explaining that both people lose access to each other's lists and purchases. Use ordinary confirmation rather than typed-email confirmation for beta.
- [x] Use `form_with`, Turbo Stream templates, and existing notifications. Preserve submitted email on validation errors and provide consistent generic success feedback without account-existence clues. Refresh affected request/friend lists and counts after successful actions.
- [x] Make controls accessible by name for both usability and system tests.


### 6. Tests and beta verification

- [x] Model tests: both association directions, pending versus accepted friends, self-friendship, unordered-pair uniqueness at the database level, participant deletion, and chainable friend queries. Exercise duplicate/crossed-request handling with database constraint tests and deterministic race-recovery tests. These are not simultaneous-connection stress tests.
- [x] Request tests: authentication, generic responses for unknown/known emails, normalized email lookup, confirmed-email boundaries, self/duplicate/crossed requests, recipient-only acceptance/decline, participant-only removal, guessed IDs, and repeated acceptance/notification behavior.
- [x] Access tests: accepted friends versus pending/unrelated/former friends, private lists, direct user/list/purchase routes, and historical purchases after friendship removal. Update existing fixtures/setup to explicitly establish friendships where access is intended.
- [x] Query regression tests: friends index list counts remain constant-query as friends are added; include zero-list friends and private lists.
- [x] Mail/job tests: recipients, content, authenticated links, enqueue timing, no duplicate/failure notifications, and deleted/resolved records before delivery.
- [x] System tests: send request, recipient accepts, both can browse friends-visible lists, recipient declines, crossed request requires acceptance, and removal revokes access. Verify generic unknown-email feedback and absence of outgoing/account-discovery UI.
- [x] Retain existing purchase/list workflows and browser login coverage; run the full suite.
- [x] Automate the complete two-user browser/email flow, including delivery through jobs and following request/acceptance email links. Local asynchronous delivery to Mailpit was verified in section 3.
- [x] Perform a final manual two-user browser/Mailpit walkthrough before beta; automated test-mail delivery does not replace this human acceptance check.

## Invitations: agreed behavior and implementation plan

### Product rules

- Use a separate Invitation model; do not use Devise Invitable or create placeholder users. Continue using Devise for account credentials and authentication.
- Every authenticated, confirmed user may invite by email. Keep invitations and existing-user friendship requests as separate workflows; do not change unknown-email friend requests into invitations.
- Create and email invitations for both new and existing accounts, with the same sender-facing behavior. Do not disclose account existence through responses, invitation listings, or identifiers. Exception: inviting an already accepted friend returns an explicit already-friends error, since that relationship is already known to the sender. Reject self-invitations too.
- Multiple people may independently invite the same email. Acceptance establishes friendship only with that invitation's sender and leaves other invitations available for later acceptance.
- Invitations never expire. Resending reuses the pending invitation and its token; cancelling deletes it and makes its acceptance link return 404. A subsequent invitation is a new row, so old links remain invalid.
- Both email variants and the acceptance page explain that acceptance establishes friendship and that friendship can be removed afterward. Existing-account email wording explains that acceptance adds a friend rather than creating an account.
- Existing recipients must authenticate as the matching account. An invitation alone never authenticates an existing account or changes its password. A signed-in user with a different email must switch accounts.
- Completing invitation-based registration confirms the invited email. Existing unconfirmed accounts require valid credentials and the matching invitation before confirmation and acceptance.
- New friendship rows use the inviter as requester and the invitee as recipient. Preserve the direction of existing pending rows when accepting them. Preserve already accepted friendships, including friendships established after sending the invitation.
- Deleting either participant deletes their associated invitations. Deleting an inviter never deletes accounts created through their invitations. Removing friendship does not reactivate an accepted invitation.

### 1. Schema and model

- [x] Add Invitation with required `inviter_id`, normalized required `email`, nullable `invitee_id`, nullable `accepted_at`, and timestamps. Both user references have foreign keys; no placeholder invitee exists before acceptance.
- [x] Add explicit inviter/invitee associations and User sent/accepted invitation associations with dependent deletion. Add pending/accepted scopes and indexes for inviter listings and invitee cleanup.
- [x] Normalize email using the same trimming/case rules as Devise. Add model validation and a partial unique database index permitting only one pending invitation per inviter/normalized email, while allowing invitations from different inviters and historical accepted rows.
- [x] Add model/database checks requiring `invitee_id` and `accepted_at` to be set together and preventing accepted self-invitations. Reject invitations to the sender's own current email before creation.

### 2. Routes, tokens, and lifecycle

- [x] Keep inviter, invited email, invitee, and acceptance state out of arbitrary update parameters. No editing the email on an existing invitation; cancel and create another instead.
- [x] Add an authenticated InvitationsController index/create/resend/destroy workflow. Scope dashboard and mutation lookups through the current user's sent invitations; guessed or foreign IDs return 404.
- [x] Add a separate token-based acceptance page usable before login. Keep GET read-only, including for mail scanners.
- [x] Add the explicit acceptance submission route with normal CSRF protection alongside the registration transaction in section 3.
- [x] Use purpose-scoped Rails signed IDs without expiration. Generate acceptance links only for recipient emails; do not expose tokens or copy-link controls to inviters. Filter invitation token parameters from logs.
- [x] Require a valid token and a pending invitation for the acceptance landing page. Missing, malformed, cancelled, or consumed invitations return 404 without changing accounts or friendships. Recheck pending state under the invitation lock on submission.
- [x] Create accepts only email, derives inviter from current_user, and rejects self/already-friend invitations. Return consistent success feedback and listing data for other existing and nonexistent accounts.
- [x] Repeated create reuses the existing pending row and does not silently resend. Provide an explicit resend action; handle pending-row uniqueness races without duplicate rows or notifications.
- [x] Resend and cancellation lock and recheck the pending invitation. Accepted invitations cannot be resent or cancelled. Cancellation deletes only the invitation, never a user or friendship.
- [x] Prepare and render responses outside transactions. Enqueue email only after commit; preserve explicit controller success/failure branches.

### 3. Registration and existing-account acceptance

- [x] Review current Devise routes/controllers and gate both registration GET and POST on a valid pending invitation. Remove unrestricted signup navigation while preserving ordinary login, password recovery, account editing, and reconfirmation.
- [x] New-user acceptance asks for username/password/password confirmation and binds email server-side to the invitation. Preserve normal User validations and submitted non-secret values on failure.
- [x] In one transaction, lock/recheck the invitation, create the confirmed User, establish accepted friendship, and populate invitation invitee/accepted_at. Failure rolls back all three; cancellation winning the lock prevents registration.
- [x] Existing confirmed recipients sign in normally and return to the invitation page for explicit acceptance. Require the account's current email to match; never match a pending `unconfirmed_email`. Do not consume the invitation merely by signing in.
- [x] Show a clear account-switch flow for a signed-in recipient whose current email does not match. Preserve the invitation across the switch without an arbitrary external return URL.
- [x] Implement an explicit credential-verification path for existing unconfirmed accounts, since ordinary Devise sign-in rejects them. Confirm and authenticate only after valid credentials, matching invitation email, and successful transactional acceptance. Preserve applicable Devise lockout/authentication safeguards rather than bypassing them with a password-only shortcut.
- [x] Handle an account being created or its email changing between page load and submission. Recheck account/email state on submission; never overwrite an existing account or turn the invitation into password-reset authority.
- [x] Create friendship with inviter/requester and invitee/recipient; accept an existing pending pair in either direction without reversing it; leave accepted pairs unchanged. Handle unordered-pair uniqueness races without duplicate rows or a failed acceptance.
- [x] Leave other invitations to the same email pending. Their acceptance later follows the existing-account flow. Never automatically accept all invitations after signup.
- [x] Make repeated/concurrent acceptance create at most one account, one friendship pair, and one acceptance transition. Define a consistent lock order for invitation, user, and existing friendship operations to avoid introducing deadlocks.
- [x] Preserve registration/admin and welcome notifications, enqueueing once after a successful commit. Move the invitation welcome trigger out of the confirmation-controller-only path; invitation signup should not send a redundant confirmation email. Existing-account acceptance must not send new-account welcome/admin notifications.
- [x] Avoid duplicate friendship-request/acceptance notifications as a side effect of invitation acceptance. Invitation email provides the initial notification; no new invitation-accepted email is required for beta.

### 4. Email jobs

The basic mailer/job was implemented with section 2 so create/resend queue real email. Section 3 added acceptance integration and job-delivered email/browser tests. Mailpit verification remains.

- [x] Add localized HTML/text invitation emails with new-account and existing-account wording, inviter identity, friendship consent/removal explanation, and the acceptance link. Do not include wishlist/purchase details.
- [x] Deliver only inside a background job, following existing mail/job conventions. Pass the invitation ID, load current state, and generate its signed link inside the job; controllers never send email synchronously.
- [x] Choose wording from current account state at delivery time; the acceptance page always resolves current state independently. A user can register between delivery and following the link.
- [x] Skip missing, cancelled, accepted, or otherwise inapplicable invitations when jobs execute. Mail failures must not undo saved invitations. A mail already handed off cannot be recalled, but its cancelled/accepted link grants no new authority.
- [x] Enqueue one job on successful creation and one on each successful explicit resend, after commit. No jobs for errors, duplicate create, rolled-back changes, or unauthorized requests.
- [x] Verify async delivery and both email variants through Mailpit. Sender feedback deliberately uses sent/resent wording; users do not need queue implementation details. No delivery-tracking columns for beta.

### 5. UI and Turbo

- [x] Add Invitations navigation and an index with all of the current user's invited emails, pending/accepted status, an email form, and an empty state. Do not expose invitee IDs, profile links, usernames, or pre-acceptance account-existence clues.
- [x] Pending invitations have accessible Resend and Cancel controls; cancellation uses normal Turbo confirmation. Accepted invitations show history without resend/cancel controls.
- [x] Use form_with, targeted Turbo Stream responses, existing notifications, and ordinary HTML fallbacks. Preserve email on validation errors and clear only the successfully submitted form.
- [x] Acceptance page clearly identifies the inviter and invited email, explains friendship consent, and presents registration, matching-account sign-in/acceptance, or account-switch instructions as appropriate. Do not expose a public user directory or unrelated profiles.
- [x] Provide useful registration/credential errors without consuming the invitation or losing its context. Do not echo passwords into responses, URLs, or logs.
- [x] After success, show an appropriate authenticated destination and confirmation of friendship. Keep expired-invitation UI out of scope because invitations do not expire.

### 6. Tests and verification

- [x] Model/database tests: email normalization, required associations, acceptance-field consistency, self-invitation, one pending row per sender/email, multiple inviters, accepted history, and deletion of either participant without deleting other accounts.
- [x] Request tests: authentication and scoped dashboard/resend/cancel authorization; self/already-friend errors; equivalent existing/unknown-account responses and listings; duplicate create; resend enqueue behavior; and cancellation/accepted-state restrictions.
- [x] Token/registration tests: unrestricted registration GET/POST denied, missing/tampered/wrong-purpose/cancelled/consumed tokens rejected, old links remain invalid after reinvitation, and no time-based expiration. GET never mutates state.
- [x] Acceptance tests: server-bound email, normal validation errors, confirmed signup without redundant confirmation, matching existing account, wrong signed-in account, unconfirmed credentials, and current versus pending changed email. Invalid credentials never confirm or authenticate an account.
- [x] Friendship tests: new row direction, pending pair in both directions, already accepted pair, independent remaining invitations, repeat acceptance, and removal not reactivating invitations.
- [x] Transaction/race regression tests: cancellation versus acceptance, duplicate invitation creation, simultaneous account/pair creation, rollback of partial work, and notification enqueue after commit exactly once per intended event. Coverage uses deterministic competing-change simulations and database constraint tests, not simultaneous-connection stress tests.
- [x] Mail/job tests: both recipient variants, consent wording, acceptance URLs, creation/resend timing, deleted/accepted records before execution, and no new-account notifications for existing recipients.
- [x] System tests: invite new user, follow job-delivered email, register and browse the inviter's friends-visible lists; existing-user acceptance; wrong-account switching; targeted validation errors; resend/cancel; and acceptance of a second sender's invitation after signup.
- [x] Update the existing registration integration/system tests for invitation-only entry while retaining real browser login and the complete successful registration workflow. Run the full suite and existing style checks.
- [x] Manually walk through new-user and existing-user invitation flows with two browser sessions and Mailpit before beta. Verify cancelled links and independent invitations too.

### 7. Setup and documentation

- [x] Document invitation-only signup, independent invitations, confirmation on acceptance, cancellation, and background-worker requirements in README/project context.
- [x] Document console-based creation of the first confirmed user using normal validations. Existing accounts remain valid without retrospective invitations. An interactive bootstrap rake task is optional later work, not a prerequisite for this feature.
- [x] Keep automatic invitations from friend-request forms, token rotation on resend, expiration, delivery tracking, invitation-acceptance notification emails, and invitation limits out of scope for beta.

## Family beta: production deployment

### Agreed scope and current host

- Deploy Wishlist on the new `dynamicsites-next` droplet created through Rancher Machine (reported Docker Engine 29.9.2). Old-host compatibility attempts are concluded: Bookworm thread creation and Alpine permission checks fail under its old seccomp runtime. Leave the old droplet serving its existing sites while Wishlist is deployed independently.
- Deploy only Wishlist and its Nginx/Certbot proxy on the new host for now. The user may retire card_tracker/music_wiki, is upgrading portfolio separately, and wants spritesheet's temporary-file issues fixed before considering migration. Those applications are not prerequisites for Wishlist beta.
- Keep Rancher Machine and remote image builds. Add Wishlist as a git submodule under `dynamic_sites/sites/wishlist`, alongside existing sites. `dynamic_sites/docker-compose.yml` remains the deployment entry point and shows the web, dedicated PostgreSQL, and separate Solid Queue worker services. Reference the submodule's production Dockerfile directly; no symlink is needed.
- Prefer three explicit service definitions in the parent Compose file for beta. Local Compose 2.38.2 supports include if later useful; inclusion must preserve predictable build/env paths and the parent entry point. Avoid parallel configuration sources that drift.
- Retain the Nginx/Certbot approach for HTTPS, but give the new host a Wishlist-only proxy configuration. The existing proxy Dockerfile copies legacy site upstreams and must not be used unchanged when those services are absent. The purchased domain is `mywishlist.top`.
- Use Resend's free plan (SMTP2GO signup failed). Send all application and Devise mail from `Wishlist <wishlist@mywishlist.top>`; no monitored inbox, and replies should bounce. Verify the incoming DNS arrangement without adding null MX to the sending domain, which can harm outbound acceptance.
- Expect approximately 9–10 users and little concurrent traffic. Short deployment downtime is acceptable. Keep production secrets in 1Password and untracked runtime environment files. No new paid monitoring service.
- Automated backups are explicitly deferred for beta: the user accepts potential data loss and will communicate this to family. Persistent storage is still required. Existing Spaces storage is available for the later backup project.

### 0. Host recovery completed

- [x] Inspect droplet capacity: 2 vCPUs, 4 GB RAM, 80 GB disk; observed 2.2 GB available memory and mostly idle CPUs. No additional droplet needed on capacity evidence alone; measure actual build/runtime usage before concluding fit.
- [x] Identify the compatibility baseline: Ubuntu 16.04.6, kernel 4.4.0-210, Docker 19.03.2/API 1.40, containerd 1.2.6. Local Rancher Machine is v0.15.0-rancher131; Docker client 28.3.2 negotiates down to API 1.40.
- [x] Recover disk space using plain `docker image prune` and deletion of old, regular `/tmp/magick-*` and `/tmp/RackMultipart*` files in spritesheet. After cleanup, `/tmp` is 44 KB, spritesheet's writable layer is about 8.85 MB, and the droplet has about 41 GB available (49% used).
- [x] Regenerate expired client certificates and verify the remote Docker connection. Certificate regeneration coincided with a daemon restart; existing web apps required manual startup because they lack restart policies. User confirms all existing sites are working again.
- Docker-managed JSON logs still occupy roughly 10.6 GB, mainly the three Rails apps and Nginx. Rotation and further cleanup are deferred to the infrastructure work; do not silently modify Docker's log files or remove volumes.

### 1. Production image and compatibility gate

- [x] Review and finish Wishlist's `Dockerfile.production`: explicit production base, non-root runtime, precompiled assets, development/test gems excluded, and no secrets in the image/build arguments. Keep the submodule as build context so its `.dockerignore` excludes local credentials.
- [x] Ensure asset precompilation works without a production database or production secrets, including configuration that currently uses ENV.fetch. Use build-only non-secret placeholders where needed rather than leaking runtime settings into image layers.
- [x] Resolve the observed Ruby pull/thread failures on Docker 19.03.2: a Docker schema-2 archive loads successfully, and the user confirmed Ruby 4.0.6 on Alpine 3.24.1 creates threads with default seccomp enabled. Production Dockerfile now selects `ruby:4.0.6-alpine3.24`; its matching archive is ready. PostgreSQL and the complete application still require remote testing (docs/production-image.md).
- [x] Build the production application on the new `dynamicsites-next` host and verify UID 1000, native libraries, thread creation and temporary-file operations with default security settings. The user confirmed these checks passed. Old-host build attempts are concluded; do not resume legacy-builder/seccomp workarounds.
- [x] Verify new-host PostgreSQL startup, Rails database preparation, web health/login and worker registration: PostgreSQL 18.6, primary schema 20261022143156, cache/queue/cable schema 1, `/up` and `/login` succeeded, and a Solid Queue Worker process registered. Actual remote job delivery remains a separate check.
- [ ] Measure peak build memory/disk and runtime memory. Keep concurrency modest; do not treat the idle snapshot as a build-capacity guarantee. If compatibility fails beyond a reasonable configuration fix, discuss a supported host/runtime before proceeding.
- [ ] Keep the last deployed image/commit available for a simple code rollback. Do not introduce registry/CI or remote-build workflow changes for beta.

Image and runtime checks are documented in `docs/production-image.md`. Local production tests passed database preparation, web/assets and processing by a separate worker. User confirmed the new host's image/native checks, database schemas, web/login, worker registration, public TLS, initial list/item creation and invitation-job execution. As of November 5 the user reports multiple family accounts have logged in successfully. Additional smoke/restart checks are documented for future use, not rerun against live family data. Resource peaks remain unchecked. Runtime database configuration still evaluates test ENV.fetch entries; the examples in `docs/deployment` supply unused placeholders until that requirement is cleaned up.

### 2. Parent Compose integration and persistence

- [x] User added Wishlist's submodule and web/db/worker definitions to dynamic_sites. Context is sites/wishlist, runtime env files are local to the deployment client. Assistant still has only read authorization for that parent repo.
- [x] Share `wishlist:production` between web and the separate `bin/jobs` worker. The standard queue configuration consumes all queues; actual email delivery still needs live verification.
- [x] Pin PostgreSQL to 18.6-alpine3.24 with its own volume at `/var/lib/postgresql`, container and credentials. User prepared primary/cache/queue/cable successfully in the dedicated instance.
- [x] Keep the database port unpublished; let Nginx reach the web service through the parent stack's networking. Do not publish another host port 80/443. Keep development bind mounts, Mailpit, Selenium, and development commands out of production.
- [x] Add restart policies for all three Wishlist services. Add explicit health checks compatible with the actual daemon. Verify recreation preserves database data and document that volumes are persistence, not backups.
- [x] Start with one modest Puma process and one queue worker process with a small thread count. Keep required queue maintenance running; tune using measured memory/connection usage rather than adding concurrency for ten users.

### 3. Runtime settings, domain, and SMTP

- [x] Purchase the domain: `mywishlist.top`.
- [x] Prepare and locally verify the Wishlist-only proxy using jonasal/nginx-certbot:6.2.0-nginx1.31.8-alpine. User integrated it as config/nginx/Dockerfile and mywishlist.conf; public DNS/certificate issuance and curl/browser checks passed. Deployment examples now match those filenames and the reviewed TLS 1.2 cipher policy.
- [x] Use `mywishlist.top` consistently in DNS, Nginx, Rails URL/host settings, and email senders. Configure the existing proxy/Certbot for its certificate and forwarded HTTPS headers; let the Wishlist image serve precompiled assets.
- [ ] Generate/store stable production signing secrets in 1Password. Supply SECRET_KEY_BASE and any required RAILS_MASTER_KEY consistently to web/worker at runtime, using untracked files with restricted permissions. Preserve signing material across rebuilds so outstanding invitations continue working.
- [x] Resolve SMTP provider signup: admin@mywishlist.top forwards to personal email; SMTP2GO rejected signup, but Resend account creation succeeded.
- [x] Create the Resend account and verify sending-domain DNS for mywishlist.top, preserving Namecheap forwarding records.
- [ ] Verify replies to the unmonitored sender bounce as intended. Resend outbound SMTP does not provide an inbound mailbox by itself.
- [x] Test Resend SMTP directly from the droplet: Python authenticated with STARTTLS on smtp.resend.com:2587 and sent wishlist@mywishlist.top mail to the user's inbox (not spam).
- [x] Configure SMTP authentication, STARTTLS, connection timeouts, and application/Devise senders through Rails runtime configuration. Defaults use Resend port 2587; actual credentials must still be supplied in the remote app.env. Local production settings/rendering checks passed without external delivery.
- [x] Separate registration alerts from DEVISE_MAILER_SENDER: optional REGISTRATION_NOTIFICATION_EMAIL selects an existing account; blank/unset disables alerts. Regression tests cover separate sender/recipient, normalization, unset and missing-account behavior. Set the user's account email in the real app.env if alerts are desired.
- [x] Verify real worker-delivered invitations, welcome, password recovery, and friendship notifications with appropriate recipients. Test bounce/no-reply behavior and avoid exposing secrets in shared diagnostic output.

### 4. Deployment sequence and beta verification

- [x] Write a complete Rancher Machine deployment/operations runbook for copying into dynamic_sites/README.md: target selection, fresh provisioning/configuration, initial install, scoped routine updates and proxy deployment. See docs/deployment/runbook.md.
- [x] Document DB readiness, all four database connections/schema checks, one-off db:prepare before worker startup, and first confirmed-user bootstrap with hidden password input and normal validations.
- [x] Document optional container/HTTP/TLS/asset/worker/email/browser smoke checks and explicit restart/recreation checks. User requested instructions rather than rerunning live smoke tests; no new production tests/restarts were performed for this documentation task. Previous local isolated checks remain the implementation evidence.
- [x] Record user-confirmed deployment and family use. The runbook includes two-session/new/existing-account invitation checks, privacy/purchase/reveal/cancellation/removal spot checks for future relevant releases; these extra scenarios are not claimed newly exercised.
- [x] Document capacity inspection, deployment records with parent/submodule revisions and running image IDs, secret locations without secret values, code rollback limits, and manual fresh-host data recovery. Actual peak measurement, automated backups and a restore rehearsal remain separate unfinished infrastructure work.

### 5. Minimal free monitoring

- [ ] Choose a free external HTTPS monitor with personal-email alerts, checking about every five minutes. No paid Sentry/Grafana setup for beta. Distinguish external DNS/TLS/proxy reachability from the container being alive.
- [ ] Use /up for basic Rails availability and decide a small readiness check for required databases. PostgreSQL should have a readiness check. Do not expose connection details or user data in health responses.
- [ ] Monitor actual queue processing with a periodic queued heartbeat to a free external service, such as Healthchecks.io, and surface failed email jobs. Alert delivery should not depend solely on Wishlist's own SMTP path.
- [ ] Document status/log inspection and manual recovery. A Docker unhealthy status alone does not trigger its restart policy; do not imply automatic recovery that has not been configured and tested.

## Immediately after beta deployment: infrastructure upgrades and maintenance

This is the next high-priority project after Wishlist is running, not optional long-term polish. Preserve the user's current deployment workflow for beta; plan the infrastructure transition separately.

- [ ] Move to a supported host OS, kernel, Docker/container runtime, and compatible Rancher Machine/client workflow. Plan migration/recovery before altering the only running host; Ubuntu 16.04 is beyond ESM without Legacy coverage.
- [ ] Introduce automated database backups to storage off the droplet, potentially the existing DigitalOcean Space, and test restoration. Cover the other database sites as well as Wishlist, and retain recovery secrets in 1Password.
- [ ] Add automatic disk monitoring and bounded cleanup. Document the verified image-pruning and targeted temporary-file cleanup commands, with their effects and the distinction between host Docker storage and application temporary files. Never use routine volume pruning as a disk-management policy.
- [ ] Configure bounded Docker stdout/stderr logs for existing services and recreate them deliberately to apply the settings. Handle Nginx/application file logs separately; Docker log limits do not rotate those files.
- [ ] Investigate spritesheet's historical ImageMagick scratch-file and Rack-upload retention, fix cleanup/resource limits, and add an age-based safety sweep where appropriate. The 2022 magick files do not establish ongoing bot activity; do not assert an unconfirmed cause.
- [ ] Add restart policies to the existing web apps and verify recovery after a daemon restart. Inspect proxy startup behavior when upstreams are temporarily unavailable.
- [ ] Review remote build peaks, retained images/rollback history, log retention, and monitoring across both droplets. Consider registry/local-build changes later rather than expanding the beta deployment task.

## Deliberate choices to retain

- Multiple historical purchases are allowed; no unique `(list_item_id, user_id)` index.
- Parent access checks stay in controllers; purchase operation predicates stay in the model.
- Turbo handles forms; Stimulus handles client behavior. No custom-fetch form replacement or notification MutationObserver needed.
- Keep explicit controller response branches and rendering outside transactions.
- Keep both new-item forms and their separate UI identities. Perfect no-JavaScript handling remains low priority.
