class RegistrationNotificationJob < ApplicationJob
  queue_as :registration_notification

  def perform(user)
    notification_recipients.each do |notification_recipient|
      RegistrationMailer.notification_message(notification_recipient, user).deliver_now
    end
  end

  private

  def notification_recipients
    # TODO: Add user roles and select users with admin role.
    User.where(email: ENV.fetch("DEVISE_MAILER_SENDER"))
  end
end
