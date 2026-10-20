require "test_helper"

class FriendshipsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    @requester = users(:sean)
    @recipient = users(:casie)
    @stranger = users(:amelia)
    @requester.confirm
    @recipient.confirm
    @stranger.confirm
    confirm_and_sign_in @requester
  end

  test "creation uses normalized confirmed email and ignores submitted participants and acceptance" do
    assert_difference "Friendship.count", 1 do
      post friendships_path, params: { friendship: {
        email: "  #{@recipient.email.upcase}  ", requester_id: @stranger.id,
        recipient_id: @stranger.id, accepted_at: Time.current
      } }
    end

    assert_redirected_to friends_path

    friendship = Friendship.sole

    assert_equal @requester.id, friendship.requester_id
    assert_equal @recipient.id, friendship.recipient_id
    assert_nil friendship.accepted_at
  end

  test "unknown email and known email have identical generic response without identifying the recipient" do
    post friendships_path, params: { friendship: { email: "unknown@example.com" } }

    unknown_response = [ response.status, response.location, flash.to_hash ]

    assert_empty Friendship.all

    post friendships_path, params: { friendship: { email: @recipient.email } }

    assert_equal unknown_response, [ response.status, response.location, flash.to_hash ]
    assert_not_includes response.body, @recipient.username

    follow_redirect!

    assert_select "a[href='#{friend_lists_path(@recipient)}']", count: 0
    assert_not_includes response.body, @recipient.email
  end

  test "unconfirmed users and pending email changes cannot receive requests" do
    @recipient.update_columns(confirmed_at: nil)

    assert_no_difference "Friendship.count" do
      post friendships_path, params: { friendship: { email: @recipient.email } }

      assert_redirected_to friends_path
    end

    @recipient.update_columns(confirmed_at: Time.current, unconfirmed_email: "pending@example.com")

    assert_no_difference "Friendship.count" do
      post friendships_path, params: { friendship: { email: "pending@example.com" } }

      assert_redirected_to friends_path
    end

    assert_difference "Friendship.count", 1 do
      post friendships_path, params: { friendship: { email: @recipient.email } }
    end
  end

  test "repeated outgoing requests remain generic and do not duplicate the relationship" do
    friendship = create_friendship

    assert_no_difference "Friendship.count" do
      post friendships_path, params: { friendship: { email: @recipient.email } }
    end

    assert_redirected_to friends_path
    assert_equal I18n.t("friendships.create.success"), flash[:success]
    assert_nil friendship.reload.accepted_at
  end

  test "crossed request requires explicit acceptance and redirects to incoming requests" do
    friendship = create_friendship(requester: @recipient, recipient: @requester)

    assert_no_difference "Friendship.count" do
      post friendships_path, params: { friendship: { email: @recipient.email } }
    end

    assert_redirected_to requests_friendships_path
    assert_nil friendship.reload.accepted_at

    follow_redirect!

    assert_select "form[action='#{accept_friendship_path(friendship)}']", count: 1
  end

  test "invalid email preserves input and returns a validation page" do
    assert_no_difference "Friendship.count" do
      post friendships_path, params: { friendship: { email: "invalid" } }
    end

    assert_response :unprocessable_entity
    assert_select "input[name='friendship[email]'][value='invalid']", count: 1
  end

  test "self requests are rejected" do
    assert_no_difference "Friendship.count" do
      post friendships_path, params: { friendship: { email: @requester.email } }
    end

    assert_response :unprocessable_entity
  end

  test "already accepted friendships are not changed" do
    friendship = create_friendship(accepted_at: 1.day.ago)
    original_acceptance = friendship.accepted_at

    assert_no_difference "Friendship.count" do
      post friendships_path, params: { friendship: { email: @recipient.email } }
    end

    assert_redirected_to friends_path
    assert_equal original_acceptance, friendship.reload.accepted_at
  end

  test "only the recipient can see the incoming request" do
    friendship = create_friendship

    get requests_friendships_path

    assert_select "#friendship_#{friendship.id}", count: 0

    switch_user(@recipient)

    get requests_friendships_path

    assert_select "#friendship_#{friendship.id}", count: 1
    assert_select "span", text: @requester.username

    switch_user(@stranger)

    get requests_friendships_path

    assert_select "#friendship_#{friendship.id}", count: 0
  end

  test "recipient accepts once and cannot change participants or submitted acceptance date" do
    friendship = create_friendship

    switch_user(@recipient)

    freeze_time do
      patch accept_friendship_path(friendship), params: { friendship: { requester_id: @stranger.id, accepted_at: 1.year.ago } }

      assert_redirected_to friends_path
      assert_equal Time.current, friendship.reload.accepted_at
      assert_equal @requester.id, friendship.requester_id
    end

    accepted_at = friendship.accepted_at

    patch accept_friendship_path(friendship)

    assert_response :not_found
    assert_equal accepted_at, friendship.reload.accepted_at
  end

  %i[requester stranger].each do |role|
    test "#{role} cannot accept or decline a pending request" do
      friendship = create_friendship

      switch_user(instance_variable_get("@#{role}"))

      patch accept_friendship_path(friendship)

      assert_response :not_found

      switch_user(instance_variable_get("@#{role}"))

      assert_no_difference "Friendship.count" do
        delete friendship_path(friendship)

        assert_response :not_found
      end

      assert_nil friendship.reload.accepted_at
    end
  end

  test "recipient can decline and a later request is allowed" do
    friendship = create_friendship

    switch_user(@recipient)

    assert_difference "Friendship.count", -1 do
      delete friendship_path(friendship)
    end

    assert_redirected_to requests_friendships_path

    switch_user(@requester)

    assert_difference "Friendship.count", 1 do
      post friendships_path, params: { friendship: { email: @recipient.email } }
    end
  end

  %i[requester recipient].each do |role|
    test "#{role} can remove an accepted friendship" do
      friendship = create_friendship(accepted_at: Time.current)

      switch_user(instance_variable_get("@#{role}"))

      assert_difference "Friendship.count", -1 do
        delete friendship_path(friendship)
      end

      assert_redirected_to friends_path
      assert_empty @requester.friends
      assert_empty @recipient.friends
    end
  end

  test "stranger cannot remove an accepted friendship" do
    friendship = create_friendship(accepted_at: Time.current)

    switch_user(@stranger)

    assert_no_difference "Friendship.count" do
      delete friendship_path(friendship)

      assert_response :not_found
    end
  end

  test "GET cannot accept a friendship" do
    friendship = create_friendship

    switch_user(@recipient)

    get accept_friendship_path(friendship)

    assert_response :not_found
    assert_nil friendship.reload.accepted_at
  end

  test "stale friendship IDs fail cleanly" do
    friendship = create_friendship

    friendship.destroy!

    switch_user(@recipient)

    patch accept_friendship_path(friendship)

    assert_response :not_found

    switch_user(@recipient)

    delete friendship_path(friendship)

    assert_response :not_found
  end

  test "anonymous requests cannot access or mutate friendships" do
    friendship = create_friendship

    sign_out @requester

    assert_no_difference "Friendship.count" do
      get requests_friendships_path

      assert_response :not_found

      post friendships_path, params: { friendship: { email: @recipient.email } }

      assert_response :not_found

      patch accept_friendship_path(friendship)

      assert_response :not_found

      delete friendship_path(friendship)

      assert_response :not_found
    end

    assert_nil friendship.reload.accepted_at
  end

  test "a reverse request appearing after lookup is recovered without implicit acceptance" do
    inserted = false
    subscriber = lambda do |*, payload|
      if !inserted && payload[:sql].start_with?("SELECT") && payload[:sql].include?('"friendships"')
        inserted = true

        Friendship.create!(requester: @recipient, recipient: @requester)
      end
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      post friendships_path, params: { friendship: { email: @recipient.email } }
    end

    assert inserted
    assert_redirected_to requests_friendships_path
    assert_equal 1, Friendship.count
    assert_nil Friendship.sole.accepted_at
    assert_equal @recipient.id, Friendship.sole.requester_id
  end

  test "removal revokes direct list and purchase access despite historical purchases" do
    friendship = create_friendship(accepted_at: Time.current)
    list = lists(:christmas_list)
    item = list_items(:paint_brush)
    purchase = item.purchases.create!(user: @recipient, quantity: 1, reveal_at: 1.day.from_now)

    switch_user(@recipient)

    get friend_list_path(@requester, list)

    assert_response :success

    delete friendship_path(friendship)

    assert_redirected_to friends_path

    switch_user(@recipient)

    get friend_lists_path(@requester)

    assert_response :not_found

    switch_user(@recipient)

    get friend_list_path(@requester, list)

    assert_response :not_found

    switch_user(@recipient)

    patch friend_list_purchase_path(@requester, list, purchase), params: { purchase: { notes: "Unauthorized" } }

    assert_response :not_found

    switch_user(@recipient)

    assert_no_difference "Purchase.count" do
      delete friend_list_purchase_path(@requester, list, purchase)

      assert_response :not_found
    end

    switch_user(@recipient)

    assert_no_difference "Purchase.count" do
      post friend_list_purchases_path(@requester, list), params: { purchase: { list_item_id: item.id, quantity: 1, reveal_at: 1.day.from_now } }

      assert_response :not_found
    end

    assert_nil purchase.reload.notes
  end

  test "request notification is queued once and no email is delivered in the request" do
    assert_no_emails do
      assert_enqueued_jobs 1, only: FriendshipRequestNotificationJob do
        post friendships_path, params: { friendship: { email: @recipient.email } }
      end
    end

    friendship = Friendship.sole

    assert_enqueued_with job: FriendshipRequestNotificationJob, args: [ friendship.id ], queue: "friendship_notification"

    assert_no_enqueued_jobs do
      post friendships_path, params: { friendship: { email: @recipient.email } }
    end
  end

  test "acceptance notification is queued once and sent only by the job" do
    friendship = create_friendship

    switch_user(@recipient)

    assert_no_emails do
      assert_enqueued_with job: FriendshipAcceptanceNotificationJob, args: [ friendship.id ] do
        patch accept_friendship_path(friendship)
      end
    end

    assert_no_enqueued_jobs do
      patch accept_friendship_path(friendship)

      assert_response :not_found
    end

    assert_emails 1 do
      perform_enqueued_jobs(only: FriendshipAcceptanceNotificationJob)
    end

    assert_equal [ @requester.email ], ActionMailer::Base.deliveries.last.to
  end

  test "unknown unconfirmed invalid and self requests do not queue notifications" do
    @recipient.update_columns(confirmed_at: nil)

    [ "unknown@example.com", @recipient.email, "invalid", @requester.email ].each do |email|
      assert_no_enqueued_jobs do
        post friendships_path, params: { friendship: { email: email } }
      end
    end
  end

  test "crossed and already accepted requests do not queue notifications" do
    friendship = create_friendship(requester: @recipient, recipient: @requester)

    assert_no_enqueued_jobs do
      post friendships_path, params: { friendship: { email: @recipient.email } }
    end

    friendship.update!(accepted_at: Time.current)

    assert_no_enqueued_jobs do
      post friendships_path, params: { friendship: { email: @recipient.email } }
    end
  end

  test "decline removal and failed authorization do not queue notifications" do
    friendship = create_friendship

    switch_user(@stranger)

    assert_no_enqueued_jobs do
      patch accept_friendship_path(friendship)

      assert_response :not_found
    end

    switch_user(@recipient)

    assert_no_enqueued_jobs do
      delete friendship_path(friendship)
    end

    friendship = create_friendship(accepted_at: Time.current)

    assert_no_enqueued_jobs do
      delete friendship_path(friendship)
    end
  end

  test "request notification waits for the enclosing transaction to commit" do
    assert_enqueued_jobs 1, only: FriendshipRequestNotificationJob do
      Friendship.transaction do
        assert_no_enqueued_jobs do
          post friendships_path, params: { friendship: { email: @recipient.email } }
        end
      end
    end
  end

  test "rolled back request does not enqueue a notification" do
    assert_no_enqueued_jobs do
      Friendship.transaction do
        post friendships_path, params: { friendship: { email: @recipient.email } }

        raise ActiveRecord::Rollback
      end
    end

    assert_empty Friendship.all
  end

  test "rolled back acceptance does not enqueue a notification" do
    friendship = create_friendship

    switch_user(@recipient)

    assert_no_enqueued_jobs do
      Friendship.transaction do
        patch accept_friendship_path(friendship)

        raise ActiveRecord::Rollback
      end
    end

    assert_nil friendship.reload.accepted_at
  end

  test "email links require login and cannot grant access to unrelated accounts" do
    friendship = create_friendship(accepted_at: Time.current)

    switch_user(@stranger)

    get friend_lists_path(@recipient)

    assert_response :not_found

    sign_out @stranger

    get requests_friendships_path

    assert_response :not_found

    get friend_lists_path(@recipient)

    assert_response :not_found
    assert friendship.reload.accepted_at.present?
  end

  private

  def switch_user(user)
    sign_out @requester
    sign_out @recipient
    sign_out @stranger
    confirm_and_sign_in user
  end

  def create_friendship(**attributes)
    Friendship.create!({ requester: @requester, recipient: @recipient }.merge(attributes))
  end
end
