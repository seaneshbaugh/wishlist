class AccountsController < ApplicationController
  before_action :authenticate_user!

  def edit
    @account = current_user
  end

  def update
    @account = current_user

    if @account.update_account(account_params)
      bypass_sign_in(@account)

      flash[:success] = if @account.saved_change_to_attribute(:unconfirmed_email)
        t(".success_email_changed")
      else
        t(".success")
      end

      redirect_to edit_account_url, status: :see_other
    else
      flash.now[:error] = t(".error")

      render "edit", status: :unprocessable_entity
    end
  end

  def confirm_delete
    @account = current_user
  end

  def destroy
    @account = current_user

    if params[:confirmation] != @account.username
      @confirmation_error = t(".error_confirmation")

      return render "confirm_delete", status: :unprocessable_entity
    end

    if @account.destroy
      sign_out(:user)

      flash[:success] = t(".success")

      redirect_to root_url, status: :see_other
    else
      flash.now[:error] = t(".error")

      render "confirm_delete", status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.require(:account).permit(:username, :email, :password, :password_confirmation, :current_password)
  end
end
