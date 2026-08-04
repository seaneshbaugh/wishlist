class ConfirmationsController < Devise::ConfirmationsController
  def show
    super

    RegistrationWelcomeJob.perform_later(@user) if @user.errors.empty?
  end
end
