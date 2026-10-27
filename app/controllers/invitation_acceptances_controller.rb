class InvitationAcceptancesController < ApplicationController
  def show
    @invitation = Invitation.find_signed(params[:token], purpose: :invitation)

    raise ActiveRecord::RecordNotFound unless @invitation && @invitation.accepted_at.nil?

    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Cache-Control"] = "no-store"
  end
end
