class RegistrationsController < Devise::RegistrationsController
  def create
    super

    RegistrationNotificationJob.perform_later(@user) if @user.persisted?
  end
end
