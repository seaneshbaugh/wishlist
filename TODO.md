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

- [ ] Implement friendships and friendship-based visibility (detailed plan below).
- [ ] Add invitations for new users. Disallow signups without invitation.
- [ ] Implement revealed purchase details/anonymous attribution and owner deletion controls if desired; current owner UI displays only purchased quantities.
- [ ] Improve README setup documentation for Docker on Fedora and Ubuntu/WSL.
- [ ] Decide deployment and hosting for the family beta.

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

- [ ] Model tests: both association directions, pending versus accepted friends, self-friendship, unordered-pair uniqueness at the database level, participant deletion, and chainable friend queries. Exercise duplicate/crossed-request handling without relying only on a validation uniqueness check.
- [ ] Request tests: authentication, generic responses for unknown/known emails, normalized email lookup, confirmed-email boundaries, self/duplicate/crossed requests, recipient-only acceptance/decline, participant-only removal, guessed IDs, and repeated acceptance/notification behavior.
- [ ] Access tests: accepted friends versus pending/unrelated/former friends, private lists, direct user/list/purchase routes, and historical purchases after friendship removal. Update existing fixtures/setup to explicitly establish friendships where access is intended.
- [ ] Query regression tests: friends index list counts remain constant-query as friends are added; include zero-list friends and private lists.
- [ ] Mail/job tests: recipients, content, authenticated links, enqueue timing, no duplicate/failure notifications, and deleted/resolved records before delivery.
- [ ] System tests: send request, recipient accepts, both can browse friends-visible lists, recipient declines, crossed request requires acceptance, and removal revokes access. Verify generic unknown-email feedback and absence of outgoing/account-discovery UI.
- [ ] Retain existing purchase/list workflows and browser login coverage; run the full suite and manually verify the two-user email flow in Mailpit before beta.

### Invitation follow-up (separate implementation)

- [ ] Invitations will gate signup and reuse the email-based entry point without disclosing account existence.
- [ ] Explicitly tell invitees that accepting an invitation also establishes friendship with the inviter; invitation acceptance is consent to both account creation and friendship.
- [ ] On verified invitation acceptance, establish an accepted friendship with the inviter, not merely a pending request. Handle existing pairs, repeat acceptance, expired invitations, and deleted inviters without duplicate rows or unintended access.
- [ ] Keep email-address invitations separate from friendships between existing user IDs. Do not create placeholder users or assume that an email merely being sent establishes a relationship.

## Deliberate choices to retain

- Multiple historical purchases are allowed; no unique `(list_item_id, user_id)` index.
- Parent access checks stay in controllers; purchase operation predicates stay in the model.
- Turbo handles forms; Stimulus handles client behavior. No custom-fetch form replacement or notification MutationObserver needed.
- Keep explicit controller response branches and rendering outside transactions.
- Keep both new-item forms and their separate UI identities. Perfect no-JavaScript handling remains low priority.
