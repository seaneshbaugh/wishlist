# Project context

Imported from the previous ChatGPT conversation; updated through friendship email notifications on 2026-10-20. The code and TODO.md are the source of truth.

## Purpose and limits

A simple self-hosted wishlist for family and close friends. Authentication, JavaScript, and modern browsers are required. The public boolean now means visible to accepted friends, never anonymous visitors. Pending requests grant no access. The list UI label still needs changing from Public to Friends. Reasonable HTML fallbacks are useful; perfect no-JavaScript behavior is low priority. Hosting decisions wait until the family beta.

## Domain and authorization

Users own lists and purchases. Lists have priority-ordered, manually positioned items. Purchases have quantities and reveal dates. Owners should not see purchases before reveal. Purchasers may edit/delete their own unrevealed purchases; list owners may delete revealed purchases. Private lists deny non-owner access, including purchase operations.

Non-owners see visible items when quantity remains or they have any historical purchase for the item. Historical purchases deliberately preserve item visibility while the list remains accessible; removal of friendship revokes list and purchase access without deleting purchase history. Multiple historical purchases per user/item are allowed; at most one currently unrevealed purchase is intended. Do not add a unique user/item purchase index.

Parent accessibility belongs in scoped controller lookups; purchase operation rules belong in model predicates. Purchase mutations lock the parent item to prevent simultaneous validations against the same remaining quantity. Responses render outside transactions.

## Architecture and preferences

Use conventional explicit Rails actions, `form_with`, Turbo Stream templates, and Stimulus for browser behavior. Successful item/purchase operations replace the list-items component; validation failures replace only the submitted form. Two new-item forms use explicit IDs submitted separately from domain parameters. New forms reset on successful Turbo submission. Notifications manage their own fade/removal.

Prefer clear `find_*` resource lookup and `load_*` view preparation. Keep render calls visible in actions. Avoid premature service objects, concerns, authorization frameworks, and generic responders. A little repetition is welcome when it keeps control flow readable. Comments explain concrete failure modes.

The developer has extensive professional Rails experience (since 2006) and is learning Stimulus, Turbo, and Rails system tests. Explain browser lifecycle and testing idioms as work proceeds. Favor meaningful workflow tests and exhaustive server rule coverage over fragile browser test counts.

## Development and verification

Docker Compose on both Fedora (ThinkPad) and Ubuntu/WSL. Rails runs in `web`, PostgreSQL in `db`, and remote Firefox in `selenium` under the `system-test` profile. Capybara serves on `web:3001`. Minitest is used; retain the real browser login test and full registration integration flow.

The original review findings are fixed and covered by model, request, and browser tests. Creation and reordering lock the relevant parent; purchase update/delete reload and reauthorize after locking the item. Index visible-item counts use a grouped query. Existing purchases can retain or decrease quantity after an owner lowers the requested amount.

## Friendship progress and routes

Friendship has requester/recipient users and nullable accepted_at, with a database check against self-friendship and an unordered-pair unique index. User#friends is a chainable relation covering accepted friendships in either direction. Existing users are never connected automatically; tests create relationships explicitly.

The request lifecycle and basic pages are implemented: normalized confirmed-email lookup, generic responses for unknown/new/duplicate outgoing requests, explicit acceptance for crossed requests, recipient-only acceptance/decline, and either-party removal. No outgoing-request list, user directory, or automatic crossed-request acceptance. Request and acceptance emails enqueue after commit from FriendshipsController and deliver only inside dedicated background jobs on the friendship_notification queue. Jobs take a friendship ID and skip deleted or inapplicable records. Duplicate outgoing requests and repeated acceptance do not enqueue extra notifications. Local async-job delivery to Mailpit is verified; production worker verification remains hosting work. Friendship forms now use Turbo Stream templates: creation resets only the email form, validation replaces that form with preserved input and an inline error, and acceptance/removal refresh friend and incoming-request collections without clearing email drafts. All stream responses append the existing transient notifications. Crossed requests deliberately redirect to incoming requests; HTML fallbacks retain conventional redirects.

FriendsController#index uses /friends. FriendshipsController handles POST /friendships, GET /friendships/requests, PATCH /friendships/:id/accept, and DELETE /friendships/:id. Nested list/purchase routes use /friends/:friend_id/lists with accepted-friend lookup. Old /users routes are removed; /friends/your-own-name and profile pages are intentionally unavailable. Owners use /lists and DELETE /lists/:list_id/purchases/:id for revealed purchases, including on private lists.

Invitation-only signup remains a separate feature. Accepting an invitation should establish friendship with the inviter, with explicit consent wording. See TODO.md for the full agreed plan and remaining work.

Friendship coverage audit: automated section 6 coverage is complete. Added constant-query friend-index checks, pending/unrelated access denial despite purchase history, deterministic uniqueness-conflict recovery, acceptance commit timing, both participant-deletion state/direction combinations, and a two-user browser workflow following job-delivered email links. The full suite passed with 291 tests and 1,175 assertions. A final manual two-user browser/Mailpit beta walkthrough and live production-worker verification remain unchecked in TODO.md. No application changes were needed for this audit.
