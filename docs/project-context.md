# Project context

Current through invitation documentation on 2026-10-29. The code and TODO.md are
the source of truth; README.md documents setup and user-facing behavior.

## Purpose and limits

A simple self-hosted wishlist for family and close friends. Authentication,
JavaScript, and modern browsers are required. Lists labelled Friends are visible
only to accepted friends; Private lists are owner-only. The database still uses
the `public` boolean for Friends visibility. There are no anonymous public lists,
user directory, friend-of-friend access, or friend profile pages. Reasonable HTML
fallbacks are useful; perfect no-JavaScript behavior is low priority. Hosting is
still to be decided for the family beta.

## Domain and authorization

Users own lists and purchases. Lists have manually positioned items sorted by
priority then position. Owners should not see purchases before their reveal date.
Purchasers may edit/delete their own unrevealed purchases; list owners may delete
revealed purchases, including on private lists. Private lists deny all non-owner
access, including purchase operations.

Within an accessible list, non-owners see visible items when quantity remains or
they have any historical purchase for the item. Historical purchases never
bypass list privacy or missing friendship. Removing friendship revokes list and
purchase access on subsequent requests without deleting purchase history.
Multiple historical purchases per user/item are allowed, with at most one
currently unrevealed purchase. Do not add a unique user/item purchase index.

Parent accessibility belongs in scoped controller lookups; purchase operation
rules belong in model predicates. Purchase mutations lock the parent item;
update/delete reload and reauthorize after locking. Existing purchases can retain
or decrease quantity after an owner lowers the requested amount. Creation and
reordering lock the relevant parent; index visible-item counts use grouped
queries. Original review findings are fixed and covered by regression tests.

## Architecture and preferences

Use conventional explicit Rails actions, form_with, Turbo Stream templates, and
Stimulus for browser behavior. Keep render calls and success/failure branches
visible in actions; render outside persistence transactions. Prefer find_* for
resource lookup and load_* for view preparation. Prefer explicit if/else over
ternaries. Domain validation errors belong in models, including self-invitation
and already-friend rules. Reused pending invitations must still be validated.

Avoid premature service objects, concerns, authorization frameworks, generic
responders, and custom-fetch form replacement. A little repetition is welcome
when it keeps control flow readable. Comments explain concrete failure modes.

Successful item/purchase operations replace the list-items component; validation
failures replace only the submitted form. The two new-item forms use separate
UI identities submitted outside domain parameters. New forms reset only after
success. Notifications handle their own fade/removal.

The developer has professional Rails experience since 2006 and is learning
Stimulus, Turbo, and system tests. Explain conventions and browser/test behavior.
Favor meaningful browser workflows and focused server-side invariant tests over
fragile browser test counts. All email delivery must run in jobs, never block a
web request. Sender feedback deliberately says sent/resent, not enqueued.

## Friendships

Friendship has requester/recipient users and nullable accepted_at, with a database
self-friendship check and unordered-pair unique index. One row represents the
relationship. User#friends is chainable and includes accepted pairs in either
direction. Existing users are never connected automatically.

Requests use normalized current confirmed email. Unknown/new/duplicate outgoing
requests receive generic feedback; there is no outgoing-request list. Incoming
requests identify the requester. Crossed requests require explicit acceptance.
Only the recipient can accept/decline pending requests; either accepted
participant can remove friendship. Decline/removal deletes the row without
history or notification. No blocking, expiration, or transitive friendship.

FriendsController#index is /friends. FriendshipsController handles POST
/friendships, GET /friendships/requests, PATCH /friendships/:id/accept, and DELETE
/friendships/:id. Nested browsing/purchases use /friends/:friend_id/lists with
accepted-friend lookup. Owners use /lists and DELETE
/lists/:list_id/purchases/:id for revealed purchases. Old /users routes and
/friends/your-own-name are unavailable.

Friendship forms use targeted streams, preserving unrelated email drafts.
Crossed requests navigate to incoming requests; HTML fallbacks redirect normally.
Request/acceptance notification jobs enqueue after commit, skip missing/resolved
records, and deliver on friendship_notification. Local Mailpit delivery was
verified; final manual beta and production-worker checks remain in TODO.md.

## Invitations and acceptance

Invitation is separate from User: required inviter/email, optional invitee and
accepted_at, and timestamps. Email is trimmed/downcased. Database checks require
invitee/accepted_at together and distinct participants. A partial unique index
permits one pending invitation per inviter/normalized email, with independent
invitations from different senders and accepted history. Deleting either user
deletes associated invitations without deleting another account.

Every confirmed user may invite. Self/already-friend invitations are errors;
otherwise existing and unknown accounts produce consistent sender feedback and
listings. Recipient email wording distinguishes registration from sign-in and
explains friendship consent/removal. Sending creates neither user nor friendship.
Invitations and friend requests remain separate workflows.

Authenticated /invitations supports index/create, POST /invitations/:id/resend,
and DELETE cancellation, all scoped to the sender. Duplicate create reuses a
pending row without resending; explicit resend reuses its token. Cancel deletes
only a pending invitation. Accepted history has no mutation controls. Resend and
cancel recheck pending state under lock. Uniqueness conflicts recover the
existing row.

Acceptance uses purpose-scoped, non-expiring Rails signed IDs. Tokens appear in
recipient links, never the sender dashboard. Missing/malformed/wrong-purpose,
cancelled, or consumed tokens return 404. Reinvitation never reactivates an old
link. Referrer-Policy: no-referrer and Cache-Control: no-store protect token pages;
parameters are filtered from logs.

GET /invitation is read-only. POST /invitation performs explicit acceptance;
legacy GET/POST /register aliases enforce the same token requirement. New users
choose username/password; email is bound server-side. Signup confirms that email
without a second confirmation message. Existing confirmed accounts must sign in
normally and explicitly accept. Wrong-account users POST to
/invitation/switch-account, then sign in and return through a stored internal
location. Successful acceptance clears the stored location.

Existing unconfirmed accounts require valid credentials through Devise's
valid_for_authentication? and valid_password? checks, preserving lockout behavior,
then confirmation and active_for_authentication? eligibility. A pending
unconfirmed_email grants no authority and is not confirmed here. Invitation
possession alone never authenticates an existing account or resets its password.
An account appearing after user-lock selection requires a fresh submission.

The acceptance transaction locks users in ID order, then invitation, then an
existing friendship. Account/confirmation, friendship, and invitation changes
roll back together. A new friendship uses inviter/requester and invitee/recipient;
existing pair direction and accepted timestamps are preserved. Only this sender
becomes a friend; other invitations remain pending. Removing friendship cannot
reactivate an accepted invitation.

Desktop/mobile Invitations links lead to an index with email/status and empty
state. The invitation-form and invitations DOM targets support targeted streams:
create/duplicate success resets the form and refreshes history; invalid create
replaces only the form with preserved input; resend appends a notification;
cancellation refreshes history without touching a draft; failure only appends an
error. Email-specific accessible button names and Turbo confirmation are used.

## Email and setup

All delivery occurs in Active Job after commit. InvitationNotificationJob loads
current pending state by ID, selects existing/new-account wording at execution,
and generates the link inside the job. It uses invitation_notification. New
signup additionally enqueues RegistrationNotificationJob and
RegistrationWelcomeJob once. Existing-account acceptance sends neither those
jobs nor duplicate friendship notifications. All Devise notifications use
deliver_later after commit, including unlock mail, on the default queue.

Development uses the async in-process adapter and Mailpit; queued work is lost on
restart. Production uses Solid Queue. config/queue.yml consumes all queues;
run a worker via RAILS_ENV=production bin/jobs or SOLID_QUEUE_IN_PUMA=1. Production
mail/URL/sender settings remain placeholders. The production primary database key
is currently misspelled daTabase; correct it before deployment. No hosting setup
or live-worker verification has been completed.

README.md contains the Docker environment example and console bootstrap. Create
the first User using normal validations and skip_confirmation! before save!;
password prompts suppress terminal input and console echo. No bootstrap task is
implemented or required. Existing accounts need no retrospective invitation.
Automatic invitations from friend-request forms, expiration, resend token
rotation, delivery tracking, invitation limits, and invitation-acceptance emails
remain deliberately out of scope for beta.

## Development and verification

Docker Compose on Fedora/ThinkPad and Ubuntu/WSL. Rails runs in web, PostgreSQL
in db, Mailpit in mailpit, and remote Firefox in selenium under the system-test
profile. Capybara serves on web:3001. The test database is separate. Container
commands can create root-owned files in the checkout.

Minitest model/request/job/mailer/integration tests run with rails test. Browser
tests use rails test:system; test:all includes everything. System tests run
sequentially because the port/browser service is shared. Non-system tests run in
parallel above the configured threshold when invoked separately. Retain real
browser login and the complete invitation-email/registration/welcome/login flow.

Last application verification: 362 tests, 1,739 assertions, all passing, with
RuboCop and whitespace checks passing. Invitation section 6's automated audit is
complete. Race tests use deterministic competing-change simulations and database
constraints, not simultaneous-connection stress tests. Coverage includes two
independent invitations across signup, invalid/consumed tokens, access revocation,
confirmation rollback, notification commit timing, and mail failure.

Invitation documentation (section 7) is complete. Manual two-browser/Mailpit
walkthroughs and invitation SMTP verification remain unchecked, alongside live
production-worker verification. Documentation changes did not rerun the suite.
