class ListsController < ApplicationController
  def index
    @lists = visible_lists.ordered
  end

  def show
    @list = find_list
  end

  def new
    @list = List.new
  end

  def create
    @list = current_user.lists.build(list_params)

    if @list.save
      flash[:success] = t(".success")

      redirect_to list_url(@list), status: :see_other
    else
      flash.now[:error] = t(".error")

      render "new", status: :unprocessable_entity
    end
  end

  def edit
    @list = find_list
  end

  def update
    @list = find_list

    if @list.update(list_params)
      flash[:success] = t(".success")

      redirect_to edit_list_url(@list), status: :see_other
    else
      flash.now[:error] = t(".error")

      render "edit", status: :unprocessable_entity
    end
  end

  def destroy
    @list = find_list

    if @list.destroy
      flash[:success] = t(".success")

      redirect_to lists_url, status: :see_other
    else
      flash[:error] = t(".error")

      render "show", status:  :unprocessable_entity
    end
  end

  def reorder
    positions = positions_params[:positions]

    unless valid_reorder_positions?(positions)
      return render json: { error: t(".invalid_list_positions") }, status: :unprocessable_entity
    end

    lists_by_id = current_user.lists.where(id: positions.map { |position| position[:id] }).index_by(&:id)

    List.transaction do
      positions.each do |position|
        lists_by_id.fetch(position[:id].to_i).update!(position: "hello") #position[:position])
      end
    end

    head :no_content
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: t(".error"), details: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def owner
    @owner ||= begin
      if params[:user_id]
        User.friendly.find(params[:user_id])
      else
        current_user
      end
    end
  end
  helper_method :owner

  private

  def visible_lists
    if owner == current_user
      owner.lists
    else
      owner.lists.publicly_visible
    end
  end

  def find_list
    visible_lists.friendly.find(params[:id])
  end

  def list_params
    params.require(:list).permit(:name, :description, :public)
  end

  def positions_params
    params.permit(positions: [ :id, :position ])
  end

  def valid_reorder_positions?(positions)
    return false unless positions.present?

    ids = positions.map { |position| position[:id].to_i }
    positions_values = positions.map { |position| position[:position].to_i }

    ids.uniq.length == ids.length &&
      ids.sort == current_user.lists.ids.sort &&
      positions_values.sort == (0...ids.length).to_a
  end
end
