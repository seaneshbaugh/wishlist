require "test_helper"

class FriendshipMailerTest < ActionMailer::TestCase
  setup do
    @requester = users(:sean)
    @recipient = users(:casie)
    @friendship = Friendship.create!(requester: @requester, recipient: @recipient)
  end

  test "request message identifies the requester and links to authenticated requests" do
    email = FriendshipMailer.request_message(@friendship)

    assert_equal [ @recipient.email ], email.to
    assert_equal "#{@requester.username} sent you a friend request on Wishlist.", email.subject
    assert email.multipart?
    assert_includes email.html_part.body.decoded, "http://example.com/friendships/requests"
    assert_includes email.text_part.body.decoded, "http://example.com/friendships/requests"
    assert_includes email.text_part.body.decoded, @requester.username
    assert_includes email.text_part.body.decoded, "Opening this link does not accept"
    assert_not_includes email.html_part.body.decoded, "/accept"
    assert_not_includes email.text_part.body.decoded, "Christmas List"
  end

  test "acceptance message goes to the requester and links to the accepting friends lists" do
    @friendship.update!(accepted_at: Time.current)

    email = FriendshipMailer.acceptance_message(@friendship)

    assert_equal [ @requester.email ], email.to
    assert_equal "#{@recipient.username} accepted your friend request on Wishlist.", email.subject
    assert email.multipart?
    assert_includes email.html_part.body.decoded, "http://example.com/friends/#{@recipient.username}/lists"
    assert_includes email.text_part.body.decoded, "http://example.com/friends/#{@recipient.username}/lists"
    assert_includes email.text_part.body.decoded, @recipient.username
    assert_not_includes email.text_part.body.decoded, "Christmas List"
  end
end
