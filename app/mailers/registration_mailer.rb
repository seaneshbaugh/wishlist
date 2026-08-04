class RegistrationMailer < ApplicationMailer
  def notification_message(user, new_user)
    @user = user

    @new_user = new_user

    mail to: @user.email, subject: t(".subject", email: @new_user.email)
  end

  def welcome_message(new_user)
    @new_user = new_user

    mail to: @new_user.email, subject: t(".subject")
  end
end
