require "application_system_test_case"

class InvitationAcceptancesTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @inviter = users(:sean)
    @inviter.confirm
  end

  test "new recipient follows invitation email registers and browses inviter lists" do
    confirm_and_sign_in @inviter

    perform_enqueued_jobs(only: InvitationNotificationJob) do
      visit invitations_path

      fill_in "Email address", with: "newuser@example.com"

      click_button "Send invitation"

      assert_text I18n.t("invitations.create.success")
    end

    email = ActionMailer::Base.deliveries.last
    link = Nokogiri::HTML(email.html_part.body.decoded).at_css("a")["href"]

    sign_out @inviter

    visit URI.parse(link).request_uri

    fill_in "Username", with: "newuser"
    fill_in "Password", with: "short", exact: true
    fill_in "Password confirmation", with: "different"

    click_button "Create account and accept invitation"

    assert_selector "[role='alert']"
    assert_field "Username", with: "newuser"

    fill_in "Password", with: "test123456", exact: true
    fill_in "Password confirmation", with: "test123456"

    click_button "Create account and accept invitation"

    assert_current_path friends_path
    assert_text I18n.t("invitation_acceptances.create.success")
    assert User.find_by!(email: "newuser@example.com").confirmed?

    click_link @inviter.username, exact: true

    assert_current_path friend_lists_path(@inviter)
    assert_text "Christmas List"
  end

  test "existing recipient switches from wrong account signs in and explicitly accepts" do
    recipient = users(:casie)

    recipient.confirm

    invitation = @inviter.sent_invitations.create!(email: recipient.email)

    confirm_and_sign_in users(:amelia)

    visit invitation_acceptance_path(token: invitation.acceptance_token)

    assert_text "Switch accounts to accept"

    click_button "Switch accounts"

    assert_current_path new_user_session_path

    fill_in "Username", with: recipient.username
    fill_in "Password", with: "test123456"

    click_button "Sign in"

    assert_current_path invitation_acceptance_path(token: invitation.acceptance_token)
    assert_nil invitation.reload.accepted_at

    click_button "Accept invitation"

    assert_current_path friends_path
    assert_equal recipient.id, invitation.reload.invitee_id
    assert_text @inviter.username
  end

  test "unconfirmed recipient supplies password before confirming and accepting" do
    recipient = users(:casie)
    invitation = @inviter.sent_invitations.create!(email: recipient.email)

    visit invitation_acceptance_path(token: invitation.acceptance_token)

    fill_in "Password", with: "wrong"

    click_button "Accept invitation"

    assert_text I18n.t("invitation_acceptances.create.invalid_credentials")
    assert_not recipient.reload.confirmed?

    fill_in "Password", with: "test123456"

    click_button "Accept invitation"

    assert_current_path friends_path
    assert recipient.reload.confirmed?
  end

  test "signup leaves another senders invitation pending for explicit friendship acceptance" do
    other_inviter = users(:amelia)

    other_inviter.confirm

    first = @inviter.sent_invitations.create!(email: "newuser@example.com")
    second = other_inviter.sent_invitations.create!(email: first.email)

    visit invitation_acceptance_path(token: first.acceptance_token)

    fill_in "Username", with: "newuser"
    fill_in "Password", with: "test123456", exact: true
    fill_in "Password confirmation", with: "test123456"

    click_button "Create account and accept invitation"

    assert_current_path friends_path
    assert_link @inviter.username, exact: true
    assert_no_link other_inviter.username, exact: true
    assert_nil second.reload.accepted_at
    assert_not_includes other_inviter.friends, first.reload.invitee

    visit invitation_acceptance_path(token: second.acceptance_token)

    assert_text "Invitation from #{other_inviter.username}"
    assert_no_field "Username"
    assert_no_field "Password"
    assert_nil second.reload.accepted_at

    click_button "Accept invitation"

    assert_current_path friends_path
    assert_link @inviter.username, exact: true
    assert_link other_inviter.username, exact: true
    assert_equal first.invitee_id, second.reload.invitee_id
    assert_equal 1, User.where(email: first.email).count
  end
end
