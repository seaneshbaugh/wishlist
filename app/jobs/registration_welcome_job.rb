class RegistrationWelcomeJob < ApplicationJob
  queue_as :registration_welcome

  def perform(user)
    RegistrationMailer.welcome_message(user).deliver_now
  end
end
