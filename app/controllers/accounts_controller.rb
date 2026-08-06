class AccountsController < ApplicationController
  def show
    @account = current_user
  end

  def edit
    @account = current_user
  end

  def update
    @account = current_user

    if @account.update(account_params)
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
      flash.now[:error] = t(".error_confirmation")

      render "edit", status: :unprocessable_entity
    end

    if @account.destroy
      flash[:success] = t(".success")

      redirect_to root_url, status: :see_other
    else
      flash[:error] = t(".error")

      render "edit", status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.require(:account).permit(:username, :email, :password, :password_confirmation).reject { |key, value| password_keys.include?(key) && value.blank? }
  end

  def password_keys
    %w[password password_confirmation]
  end
end
