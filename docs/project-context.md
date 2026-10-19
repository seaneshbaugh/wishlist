# Project context

Imported from the previous ChatGPT conversation and checked against the repository on 2026-10-10. The code is the source of truth; the previous handoff included unimplemented suggestions.

## Purpose and limits

A simple self-hosted wishlist for family and close friends. Authentication, JavaScript, and modern browsers are required. Public lists mean accessible to other authenticated users, not anonymous visitors. Friendship-based access is future work. Reasonable HTML fallbacks are useful; perfect no-JavaScript behavior is low priority. Hosting decisions wait until the family beta.

## Domain and authorization

Users own lists and purchases. Lists have priority-ordered, manually positioned items. Purchases have quantities and reveal dates. Owners should not see purchases before reveal. Purchasers may edit/delete their own unrevealed purchases; list owners may delete revealed purchases. Private lists deny non-owner access, including purchase operations.

Non-owners see visible items when quantity remains or they have any historical purchase for the item. Historical purchases deliberately preserve item visibility while the list remains accessible. Multiple historical purchases per user/item are allowed; at most one currently unrevealed purchase is intended. Do not add a unique user/item purchase index.

Parent accessibility belongs in scoped controller lookups; purchase operation rules belong in model predicates. Purchase mutations lock the parent item to prevent simultaneous validations against the same remaining quantity. Responses render outside transactions.

## Architecture and preferences

Use conventional explicit Rails actions, `form_with`, Turbo Stream templates, and Stimulus for browser behavior. Successful item/purchase operations replace the list-items component; validation failures replace only the submitted form. Two new-item forms use explicit IDs submitted separately from domain parameters. New forms reset on successful Turbo submission. Notifications manage their own fade/removal.

Prefer clear `find_*` resource lookup and `load_*` view preparation. Keep render calls visible in actions. Avoid premature service objects, concerns, authorization frameworks, and generic responders. A little repetition is welcome when it keeps control flow readable. Comments explain concrete failure modes.

The developer has extensive professional Rails experience (since 2006) and is learning Stimulus, Turbo, and Rails system tests. Explain browser lifecycle and testing idioms as work proceeds. Favor meaningful workflow tests and exhaustive server rule coverage over fragile browser test counts.

## Development and verification

Docker Compose on both Fedora (ThinkPad) and Ubuntu/WSL. Rails runs in `web`, PostgreSQL in `db`, and remote Firefox in `selenium` under the `system-test` profile. Capybara serves on `web:3001`. Minitest is used; retain the real browser login test and full registration integration flow.

On 2026-10-10, `docker compose exec -T web bundle exec rails test:all` passed: 21 tests, 63 assertions. RuboCop on models/controllers passed with no offenses. This is a baseline, not evidence of comprehensive authorization coverage.

Already implemented relative to the handoff: `List#purchases` through-association, `unrevealed_purchase_for` use in views, one-unrevealed-purchase validation, optional reorder CSRF header, and Selenium profile. List-item reorder request coverage described in the handoff is absent from this checkout. The browser reorder test passes but still checks database state without polling.
