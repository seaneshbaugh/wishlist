require "test_helper"

class InvitationAcceptancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @invitation = users(:sean).sent_invitations.create!(email: "new@example.com")
  end

  test "anonymous GET is read only and identifies inviter and invited email" do
    assert_no_difference [ "User.count", "Friendship.count", "Invitation.count" ] do
      get invitation_acceptance_path(token: @invitation.acceptance_token)
    end

    assert_response :success
    assert_includes response.body, @invitation.inviter.username
    assert_includes response.body, @invitation.email
    assert_nil @invitation.reload.accepted_at
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "missing malformed altered and wrong purpose tokens fail" do
    token = @invitation.acceptance_token

    [ nil, "invalid", token + "x", @invitation.signed_id(purpose: :other) ].each do |invalid|
      get invitation_acceptance_path(token: invalid)

      assert_response :not_found
    end
  end

  test "tokens do not expire with time" do
    token = @invitation.acceptance_token

    travel 10.years do
      get invitation_acceptance_path(token: token)

      assert_response :success
    end
  end

  test "cancelled and consumed tokens fail and reinviting does not reactivate old link" do
    token = @invitation.acceptance_token
    inviter = @invitation.inviter

    @invitation.destroy!

    replacement = inviter.sent_invitations.create!(email: "new@example.com")

    get invitation_acceptance_path(token: token)

    assert_response :not_found

    replacement.update!(invitee: users(:casie), accepted_at: Time.current)

    get invitation_acceptance_path(token: replacement.acceptance_token)

    assert_response :not_found
  end
end
