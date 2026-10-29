require "application_system_test_case"

class InvitationsTest < ApplicationSystemTestCase
  setup do
    @inviter = users(:sean)
    confirm_and_sign_in @inviter
  end

  test "navigation creation validation and duplicate feedback work with Turbo" do
    visit friends_path

    within "nav" do
      click_link "Invitations"
    end

    assert_current_path invitations_path
    assert_text "You haven't sent any invitations."

    # Use an existing friend to reach server-side validation without bypassing
    # the browser's email field validation.
    recipient = users(:casie)

    Friendship.create!(requester: @inviter, recipient: recipient, accepted_at: Time.current)

    fill_in "Email address", with: recipient.email

    click_button "Send invitation"

    within "#invitation-form" do
      assert_text "already your friend"
    end

    assert_field "Email address", with: recipient.email
    assert_text "You haven't sent any invitations."

    fill_in "Email address", with: "new@example.com"

    click_button "Send invitation"

    assert_text I18n.t("invitations.create.success")
    assert_field "Email address", with: ""

    within "#invitations" do
      assert_text "new@example.com"
      assert_text "Pending"
    end

    assert_no_text "You haven't sent any invitations."

    fill_in "Email address", with: "new@example.com"

    click_button "Send invitation"

    assert_text I18n.t("invitations.create.already_pending")
    assert_field "Email address", with: ""
    assert_equal 1, Invitation.count
  end

  test "resend and cancellation preserve an email draft and restore empty state" do
    invitation = @inviter.sent_invitations.create!(email: "new@example.com")

    visit invitations_path

    fill_in "Email address", with: "draft@example.com"

    click_button "Resend invitation to #{invitation.email}"

    assert_text I18n.t("invitations.resend.success")
    assert_field "Email address", with: "draft@example.com"

    dismiss_confirm do
      click_button "Cancel invitation to #{invitation.email}"
    end

    assert_selector "#invitation_#{invitation.id}"

    accept_confirm do
      click_button "Cancel invitation to #{invitation.email}"
    end

    assert_text "You haven't sent any invitations."
    assert_field "Email address", with: "draft@example.com"
    assert_not Invitation.exists?(invitation.id)
  end

  test "accepted invitations are shown as history without action buttons" do
    invitation = @inviter.sent_invitations.create!(email: users(:casie).email,
      invitee: users(:casie), accepted_at: Time.current)

    visit invitations_path

    within "#invitation_#{invitation.id}" do
      assert_text invitation.email
      assert_text "Accepted"
      assert_no_button "Resend"
      assert_no_button "Cancel invitation"
    end
  end
end
